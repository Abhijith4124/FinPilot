defmodule Finpilot.Workers.AIProcessingWorker do
  @moduledoc """
  Redesigned Oban worker for processing incoming text/events through AI analysis.
  This worker:
  1. Analyzes incoming text with AI using direct tool calling
  2. Executes tools based on AI decisions
  3. Manages tasks with recursive processing
  4. Handles multi-stage task execution
  """

  use Oban.Worker, queue: :ai_processing
  require Logger

  alias Finpilot.Tasks.{Task, Instruction}
  alias Finpilot.Workers.ToolExecutor
  alias Finpilot.Services.OpenRouter
  alias Finpilot.Services.Memory
  alias Finpilot.Repo
  import Ecto.Query

  # Default AI model for processing
  @default_model "google/gemini-2.0-flash-001"

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"text" => text, "user_id" => user_id, "source" => source} = args
      }) do
    Logger.info("[AIProcessingWorker] Starting job #{job_id} for user #{user_id} from source #{source}")
    Logger.debug("[AIProcessingWorker] Job args: #{inspect(args)}")

    user_id = ensure_binary_id(user_id)

    # Build context with instructions, running tasks, and metadata
    Logger.debug("[AIProcessingWorker] Building context for user #{user_id}")
    context = build_context(text, user_id, source, args, job_id)
    Logger.debug("[AIProcessingWorker] Context built with #{length(context.instructions)} instructions, #{length(context.running_tasks)} running tasks")

    # Call AI with direct tool calling
    Logger.info("[AIProcessingWorker] Calling AI with tools for job #{job_id}")
    case call_ai_with_tools(context) do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[AIProcessingWorker] AI returned #{length(tool_calls)} tool calls for job #{job_id}")
        Logger.debug("[AIProcessingWorker] Tool calls: #{inspect(tool_calls)}")
        result = execute_tool_calls(tool_calls, user_id)
        Logger.info("[AIProcessingWorker] Job #{job_id} completed successfully")
        {:ok, result}
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI processing failed for job #{job_id}: #{reason}")
        {:error, "AI processing failed: #{reason}"}
    end
  end

  # Ensure user_id is in binary format
  defp ensure_binary_id(user_id) when is_binary(user_id), do: user_id
  defp ensure_binary_id(user_id), do: to_string(user_id)

  # Build comprehensive context for AI processing with enhanced metadata
  defp build_context(text, user_id, source, args, job_id) do
    instructions = get_active_instructions(user_id)
    running_tasks = get_running_tasks(user_id)
    relevant_memory = get_relevant_memory(user_id, text)

    %{
      text: text,
      user_id: user_id,
      source: source,
      metadata: Map.drop(args, ["text", "user_id", "source"]),
      instructions: instructions,
      running_tasks: running_tasks,
      relevant_memory: relevant_memory,
      timestamp: DateTime.utc_now(),
      process_id: self(),
      node: Node.self(),
      job_id: job_id
    }
  end

  # Get active instructions for the user
  defp get_active_instructions(user_id) do
    Logger.debug("[AIProcessingWorker] Fetching active instructions for user #{user_id}")

    instructions = from(i in Instruction,
      where: i.user_id == ^user_id and i.is_active == true,
      select: %{
        id: i.id,
        name: i.name,
        description: i.description,
        trigger_conditions: i.trigger_conditions,
        actions: i.actions,
        ai_prompt: i.ai_prompt
      }
    )
    |> Repo.all()

    Logger.debug("[AIProcessingWorker] Found #{length(instructions)} active instructions for user #{user_id}")
    instructions
  end

  # Get running tasks for the user
  defp get_running_tasks(user_id) do
    Logger.debug("[AIProcessingWorker] Fetching running tasks for user #{user_id}")

    try do
      tasks =
        from(t in Task,
          where: t.user_id == ^user_id and t.is_done == false,
          preload: [:task_stages]
        )
        |> Repo.all()
        |> Enum.map(fn task ->
          %{
            id: task.id,
            task_instruction: task.task_instruction,
            current_stage_summary: task.current_stage_summary,
            next_stage_instruction: task.next_stage_instruction,
            context: task.context,
            task_stages: task.task_stages
          }
        end)

      Logger.debug("[AIProcessingWorker] Found #{length(tasks)} running tasks for user #{user_id}")
      tasks
    rescue
      e ->
        Logger.error("[AIProcessingWorker] Error fetching running tasks for user #{user_id}: #{inspect(e)}")
        []
    end
  end

  # Get relevant memory (tasks and messages) using semantic search
  defp get_relevant_memory(user_id, text) do
    Logger.debug("[AIProcessingWorker] Fetching relevant memory for user #{user_id}")

    try do
      case Memory.find_relevant_context(user_id, text,
             task_limit: 5,
             message_limit: 10,
             threshold: 0.7
           ) do
        {:ok, %{tasks: tasks, messages: messages}} ->
          Logger.debug("[AIProcessingWorker] Found #{length(tasks)} relevant tasks and #{length(messages)} relevant messages for user #{user_id}")
          %{
            tasks: format_memory_tasks(tasks),
            messages: format_memory_messages(messages)
          }

        {:error, reason} ->
          Logger.warning("[AIProcessingWorker] Memory search failed for user #{user_id}: #{reason}")
          %{tasks: [], messages: []}
      end
    rescue
      e ->
        Logger.error("[AIProcessingWorker] Error fetching relevant memory for user #{user_id}: #{inspect(e)}")
        %{tasks: [], messages: []}
    end
  end

  # Format memory tasks for AI context
  defp format_memory_tasks(tasks) do
    Enum.map(tasks, fn task ->
      %{
        id: task.id,
        instruction: task.task_instruction,
        status: if(task.is_done, do: "completed", else: "incomplete"),
        created_at: task.inserted_at
      }
    end)
  end

  # Format memory messages for AI context
  defp format_memory_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        id: message.id,
        role: message.role,
        content: message.message,
        created_at: message.inserted_at
      }
    end)
  end

  # Call AI with direct tool calling
  defp call_ai_with_tools(context) do
    Logger.debug("[AIProcessingWorker] Building AI prompt for user #{context.user_id}")
    prompt = build_ai_prompt(context)
    Logger.debug("[AIProcessingWorker] Prompt length: #{String.length(prompt)} characters")

    Logger.debug("[AIProcessingWorker] Getting tool definitions")
    tool_definitions = ToolExecutor.tool_definitions()
    tools = OpenRouter.format_tools(tool_definitions)
    Logger.debug("[AIProcessingWorker] Using #{length(tools)} tools")

    messages = [OpenRouter.user_message(prompt)]

    Logger.info("[AIProcessingWorker] Calling OpenRouter AI with model #{@default_model}")
    result = OpenRouter.call_ai(@default_model, messages,
      tools: tools,
      system_prompt: get_system_prompt()
    )

    case result do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[AIProcessingWorker] AI call successful, received #{length(tool_calls)} tool calls")
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI call failed: #{reason}")
      other ->
        Logger.warning("[AIProcessingWorker] Unexpected AI response: #{inspect(other)}")
    end

    result
  end

  # Execute individual tool calls with better error handling
  defp execute_tool_calls(tool_calls, user_id) do
    Logger.info("[AIProcessingWorker] Executing #{length(tool_calls)} tool calls for user #{user_id}")

    Enum.with_index(tool_calls, 1)
    |> Enum.map(fn {tool_call, index} ->
      try do
        tool_name = tool_call["function"]["name"]
        tool_args = Jason.decode!(tool_call["function"]["arguments"])

        Logger.info("[AIProcessingWorker] Executing tool #{index}/#{length(tool_calls)}: #{tool_name} for user #{user_id}")
        Logger.debug("[AIProcessingWorker] Tool args: #{inspect(tool_args)}")

        case ToolExecutor.execute_tool(tool_name, tool_args, user_id) do
          {:ok, result} ->
            Logger.info("[AIProcessingWorker] Tool #{tool_name} executed successfully for user #{user_id}")
            Logger.debug("[AIProcessingWorker] Tool result: #{inspect(result)}")
            {:ok, result}

          {:error, reason} ->
            Logger.error("[AIProcessingWorker] Tool #{tool_name} failed for user #{user_id}: #{reason}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("[AIProcessingWorker] Tool execution exception for user #{user_id}: #{inspect(e)}")
          Logger.error("[AIProcessingWorker] Tool call that caused exception: #{inspect(tool_call)}")
          {:error, "Tool execution exception: #{inspect(e)}"}
      end
    end)
  end

  # Get system prompt for AI
  defp get_system_prompt do
    """
    You are FinPilot, an intelligent AI assistant that manages business operations through structured tool calls.

    CRITICAL: You MUST ONLY respond using tool calls. Never provide text responses or explanations outside of tool calls.

    Your responsibilities:
    1. Analyze incoming text from various sources (chat, email, calendar, CRM, etc.)
    2. Execute appropriate actions using the available tools
    3. Create and manage multi-stage tasks
    4. Send messages to users via the assistant_message tool
    5. Perform business operations like email sending, meeting scheduling, CRM updates

    CONTEXT SECTIONS:

    INCOMING TEXT:
    - Source: Origin of the text (chat, email, webhook, task_continuation, etc.)
    - Content: The actual message/text to process
    - Timestamp: When this processing request was made
    - Metadata: Additional context (session_id, task_id, continuation_depth, etc.)

    ACTIVE INSTRUCTIONS:
    - User-defined automation rules and preferences
    - Persistent instructions that guide all decisions for this user
    - Use these to understand workflow preferences and automation triggers

    RUNNING TASKS:
    - Currently active, incomplete tasks
    - Shows: task ID, instruction, current stage, next stage
    - Avoid duplicating work already in progress
    - Consider updating existing tasks instead of creating new ones

    RELEVANT MEMORY:
    - Semantically similar past tasks and messages
    - Helps avoid repeating previous work
    - Use for informed decision-making about task creation/updates
    - Empty for task continuations to prevent infinite loops

    TOOL USAGE RULES:
    1. ALWAYS use tool calls - never respond with plain text
    2. Use assistant_message tool to communicate with users
    3. Use create_task tool for actionable items that require multiple steps
    4. Use update_task tool to progress existing tasks
    5. Use complete_task tool when tasks are finished
    6. Only create tasks for actions supported by available tools
    7. Be proactive in identifying actionable items from incoming text
    8. Consider context from running tasks and user instructions
    9. Use relevant memory to avoid duplicating previous decisions

    Remember: Every response must be a tool call. Use assistant_message for any communication needs.
    """
  end

  # Build AI prompt with context
  defp build_ai_prompt(context) do
    instructions_text = format_instructions(context.instructions)
    tasks_text = format_running_tasks(context.running_tasks)

    """
    INCOMING TEXT:
    Source: #{context.source}
    Content: #{context.text}
    Timestamp: #{context.timestamp}

    #{if context.metadata != %{}, do: "Metadata: #{inspect(context.metadata)}\n", else: ""}

    ACTIVE INSTRUCTIONS:
    #{instructions_text}

    RUNNING TASKS:
    #{tasks_text}

    RELEVANT MEMORY:
    #{memory_text}

    Please analyze this incoming text and respond appropriately using tool calls for actions or direct messages for communication.

    Use the relevant memory context to make informed decisions and avoid duplicating previous work.
    """
  end

  # Format instructions for AI prompt
  defp format_instructions([]), do: "No active instructions."

  defp format_instructions(instructions) do
    instructions
    |> Enum.map(fn instruction ->
      "- #{instruction.name}: #{instruction.description}"
    end)
    |> Enum.join("\n")
  end

  # Format running tasks for AI prompt
  defp format_running_tasks([]), do: "No running tasks."

  defp format_running_tasks(tasks) do
    tasks
    |> Enum.map(fn task ->
      """
      Task ID: #{task.id}
      Instruction: #{task.task_instruction}
      Current Stage: #{task.current_stage_summary || "Not started"}
      Next Stage: #{task.next_stage_instruction || "None"}
      """
    end)
    |> Enum.join("\n---\n")
  end

  # Format relevant memory for AI prompt
  defp format_relevant_memory(%{tasks: [], messages: []}), do: "No relevant memory found."

  defp format_relevant_memory(%{tasks: tasks, messages: messages}) do
    tasks_section =
      if Enum.empty?(tasks) do
        "No relevant tasks."
      else
        "RELEVANT TASKS:\n" <>
          (tasks
           |> Enum.map(fn task ->
             "- [#{task.status}] #{task.instruction} (#{format_date(task.created_at)})"
           end)
           |> Enum.join("\n"))
      end

    messages_section =
      if Enum.empty?(messages) do
        "No relevant messages."
      else
        "RELEVANT MESSAGES:\n" <>
          (messages
           |> Enum.map(fn message ->
             "- [#{message.role}] #{String.slice(message.content, 0, 100)}#{if String.length(message.content) > 100, do: "...", else: ""} (#{format_date(message.created_at)})"
           end)
           |> Enum.join("\n"))
      end

    "#{tasks_section}\n\n#{messages_section}"
  end

  # Format date for display
  defp format_date(datetime) do
    case datetime do
      %DateTime{} -> DateTime.to_string(datetime)
      %NaiveDateTime{} -> NaiveDateTime.to_string(datetime)
      _ -> "Unknown date"
    end
  end
end
