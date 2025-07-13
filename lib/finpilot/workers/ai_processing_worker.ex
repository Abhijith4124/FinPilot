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

  alias Finpilot.TaskRunner
  alias Finpilot.TaskRunner.{Task, Instruction}
  alias Finpilot.Workers.ToolExecutor
  alias Finpilot.Services.OpenRouter
  alias Finpilot.Repo
  import Ecto.Query

  require Logger

  # Default AI model for processing
  @default_model "google/gemini-2.0-flash-001"


  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"text" => text, "user_id" => user_id, "source" => source} = args}) do
    user_id = ensure_binary_id(user_id)

    Logger.info("[AIProcessingWorker] Starting AI processing for user #{user_id}, source: #{source}")
    Logger.debug("[AIProcessingWorker] Processing text: #{String.slice(text, 0, 100)}#{if String.length(text) > 100, do: "...", else: ""}")

    # Build context with instructions, running tasks, and metadata
    context = build_context(text, user_id, source, args)
    Logger.info("[AIProcessingWorker] Context built with #{length(context.instructions)} instructions, #{length(context.running_tasks)} running tasks")

    # Call AI with direct tool calling
    case call_ai_with_tools(context) do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[AIProcessingWorker] AI returned #{length(tool_calls)} tool calls")
        execute_tools_and_continue(tool_calls, context)

      {:ok, :message, updated_messages} ->
        Logger.info("[AIProcessingWorker] AI returned conversational message")
        # Extract the last assistant message
        assistant_message = updated_messages
        |> Enum.reverse()
        |> Enum.find(fn msg -> msg["role"] == "assistant" end)
        handle_conversational_response(assistant_message, context)

      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI call failed: #{reason}")
        {:error, "AI processing failed: #{reason}"}
    end
  end

  # Ensure user_id is in binary format
  defp ensure_binary_id(user_id) when is_binary(user_id), do: user_id
  defp ensure_binary_id(user_id) when is_integer(user_id), do: Integer.to_string(user_id)
  defp ensure_binary_id(user_id), do: to_string(user_id)

  # Build comprehensive context for AI processing with enhanced metadata
  defp build_context(text, user_id, source, args) do
    instructions = get_active_instructions(user_id)
    running_tasks = get_running_tasks(user_id)

    %{
      text: text,
      user_id: user_id,
      source: source,
      metadata: Map.drop(args, ["text", "user_id", "source"]),
      instructions: instructions,
      running_tasks: running_tasks,
      timestamp: DateTime.utc_now(),
      process_id: self(),
      node: Node.self()
    }
  end

  # Get active instructions for the user
  defp get_active_instructions(user_id) do
    from(i in Instruction,
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
  end

  # Get running tasks for the user
  defp get_running_tasks(user_id) do
    Logger.debug("[AIProcessingWorker] Querying running tasks for user #{user_id}")

    try do
      tasks = from(t in Task,
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

      Logger.debug("[AIProcessingWorker] Successfully retrieved #{length(tasks)} running tasks")
      tasks
    rescue
      e ->
        Logger.error("[AIProcessingWorker] Error getting running tasks: #{inspect(e)}")
        []
    end
  end

  # Call AI with direct tool calling
  defp call_ai_with_tools(context) do
    prompt = build_ai_prompt(context)
    tool_definitions = get_tool_definitions()
    tools = OpenRouter.format_tools(tool_definitions)
    messages = [OpenRouter.user_message(prompt)]

    Logger.debug("[AIProcessingWorker] Calling AI with #{length(tool_definitions)} tools")

    OpenRouter.call_ai(@default_model, messages, [
      tools: tools,
      system_prompt: get_system_prompt()
    ])
  end

  # Execute tool calls and handle recursive processing
  defp execute_tools_and_continue(tool_calls, context) do
    Logger.info("[AIProcessingWorker] Executing #{length(tool_calls)} tool calls")

    # Execute all tool calls
    results = execute_tool_calls(tool_calls, context.user_id)

    # Only continue tasks if this is not already a task continuation to prevent infinite loops
    continuation_results = if context.source != "task_continuation" do
      # Check for tasks that need continuation
      updated_tasks = get_tasks_needing_continuation(context.user_id)

      # Process each task that needs continuation
      Enum.map(updated_tasks, fn task ->
        if should_continue_task?(task) do
          continue_task_processing(task, context)
        else
          {:ok, "Task #{task.id} does not need continuation"}
        end
      end)
    else
      Logger.info("[AIProcessingWorker] Skipping task continuation to prevent recursive loops")
      []
    end

    Logger.info("[AIProcessingWorker] Tool execution completed with #{length(continuation_results)} task continuations")
    {:ok, %{tool_results: results, continuation_results: continuation_results}}
  end

  # Handle conversational AI responses
  defp handle_conversational_response(message, context) do
    content = message["content"] || "I understand your message. How can I help you?"

    case context.source do
      "chat" ->
        session_id = context.metadata["session_id"]
        if session_id do
          case Finpilot.ChatMessages.create_assistant_message(session_id, context.user_id, content) do
            {:ok, _message} ->
              Logger.info("[AIProcessingWorker] Created conversational response")
              {:ok, "Conversational response created"}
            {:error, reason} ->
              Logger.error("[AIProcessingWorker] Failed to create response: #{inspect(reason)}")
              {:error, "Failed to create response"}
          end
        else
          Logger.error("[AIProcessingWorker] No session_id for chat response")
          {:error, "No session_id provided"}
        end
      _ ->
        Logger.info("[AIProcessingWorker] Conversational response for #{context.source}: #{content}")
        {:ok, "Conversational response processed"}
    end
  end

  # Execute individual tool calls with better error handling
  defp execute_tool_calls(tool_calls, user_id) do
    Logger.info("[AIProcessingWorker] Starting execution of #{length(tool_calls)} tool calls for user #{user_id}")
    
    Enum.map(tool_calls, fn tool_call ->
      try do
        tool_name = tool_call["function"]["name"]
        tool_args = Jason.decode!(tool_call["function"]["arguments"])

        Logger.info("[AIProcessingWorker] Executing tool: #{tool_name} with args: #{inspect(tool_args)}")

        case ToolExecutor.execute_tool(tool_name, tool_args, user_id) do
          {:ok, result} ->
            Logger.info("[AIProcessingWorker] Tool #{tool_name} executed successfully: #{inspect(result)}")
            {:ok, result}
          {:error, reason} ->
            Logger.error("[AIProcessingWorker] Tool #{tool_name} failed: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("[AIProcessingWorker] Exception in tool execution: #{inspect(e)}")
          {:error, "Tool execution exception: #{inspect(e)}"}
      end
    end)
  end

  # Get tasks that might need continuation after tool execution
  defp get_tasks_needing_continuation(user_id) do
    from(t in Task,
      where: t.user_id == ^user_id and t.is_done == false and not is_nil(t.next_stage_instruction),
      preload: [:task_stages]
    )
    |> Repo.all()
  end

  # Check if a task should continue processing
  defp should_continue_task?(task) do
    # Task should continue if it has a next stage and conditions are met
    not is_nil(task.next_stage_instruction) and
    not task.is_done and
    task.next_stage_instruction != ""
  end

  # Continue processing a task recursively
  defp continue_task_processing(task, original_context) do
    # Create new context for task continuation
    continuation_context = %{
      text: "Continue task: #{task.next_stage_instruction}",
      user_id: task.user_id,
      source: "task_continuation",
      metadata: %{
        "task_id" => task.id,
        "original_source" => original_context.source
      },
      instructions: original_context.instructions,
      running_tasks: [task],
      timestamp: DateTime.utc_now()
    }

    Logger.info("[AIProcessingWorker] Continuing task #{task.id} recursively")

    # Recursively call AI for task continuation
    case call_ai_with_tools(continuation_context) do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        execute_tools_and_continue(tool_calls, continuation_context)
      {:ok, :message, updated_messages} ->
        # Extract the last assistant message
        assistant_message = updated_messages
        |> Enum.reverse()
        |> Enum.find(fn msg -> msg["role"] == "assistant" end)
        handle_conversational_response(assistant_message, continuation_context)
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] Task continuation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Get system prompt for AI
  defp get_system_prompt do
    """
    You are FinPilot, an intelligent AI assistant that helps users manage their business operations.

    Your role is to:
    1. Analyze incoming text from various sources (chat, email, calendar, CRM, etc.)
    2. Understand user instructions and running tasks
    3. Respond ONLY through tool calls - never send direct messages
    4. Create, update, and manage tasks with multiple stages
    5. Execute business operations like sending emails, scheduling meetings, updating CRM

    IMPORTANT RULES:
    - You MUST respond only with tool calls, never direct messages
    - If you need to communicate with the user, use the 'create_assistant_message' or 'create_system_notification' tools
    - Tasks can have multiple stages and may require recursive processing
    - Always consider the context of running tasks and user instructions
    - Be proactive in identifying actionable items from the incoming text

    Available tools allow you to:
    - Send emails and schedule meetings
    - Create and update CRM contacts
    - Manage tasks and task stages
    - Create chat messages and system notifications
    - Wait for future responses when needed
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

    Please analyze this incoming text and respond with appropriate tool calls to handle any:
    1. New tasks that need to be created
    2. Updates to existing running tasks
    3. Communications that need to be sent
    4. Business operations that need to be performed

    Remember: Respond ONLY with tool calls, never direct messages.
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

  # AI Tool Definitions
  defp get_tool_definitions do
    [
      %{
        name: "send_email",
        description: "Send an email to one or more recipients",
        parameters: %{
          type: "object",
          properties: %{
            to: %{
              type: "array",
              items: %{type: "string"},
              description: "Email addresses of recipients"
            },
            subject: %{type: "string", description: "Email subject line"},
            body: %{type: "string", description: "Email body content"},
            cc: %{
              type: "array",
              items: %{type: "string"},
              description: "CC recipients (optional)"
            },
            bcc: %{
              type: "array",
              items: %{type: "string"},
              description: "BCC recipients (optional)"
            }
          },
          required: ["to", "subject", "body"]
        }
      },
      %{
        name: "schedule_meeting",
        description: "Schedule a meeting with participants",
        parameters: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Meeting title"},
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "Email addresses of attendees"
            },
            start_time: %{
              type: "string",
              format: "date-time",
              description: "Meeting start time in ISO 8601 format"
            },
            end_time: %{
              type: "string",
              format: "date-time",
              description: "Meeting end time in ISO 8601 format"
            },
            description: %{type: "string", description: "Meeting description (optional)"},
            location: %{type: "string", description: "Meeting location (optional)"}
          },
          required: ["title", "attendees", "start_time", "end_time"]
        }
      },
      %{
        name: "update_crm",
        description: "Update CRM system with contact or deal information",
        parameters: %{
          type: "object",
          properties: %{
            contact_email: %{type: "string", description: "Contact's email address"},
            action: %{
              type: "string",
              enum: ["create_contact", "update_contact", "create_deal", "update_deal"],
              description: "CRM action to perform"
            },
            data: %{type: "object", description: "Data to update in CRM"}
          },
          required: ["contact_email", "action", "data"]
        }
      },
      %{
        name: "create_task",
        description: "Create a new task in the TaskRunner system",
        parameters: %{
          type: "object",
          properties: %{
            task_instruction: %{
              type: "string",
              description: "Natural language instruction for the task"
            },
            context: %{type: "object", description: "Initial context data for the task"}
          },
          required: ["task_instruction"]
        }
      },
      %{
        name: "update_task_stage",
        description: "Update the current stage of an existing task",
        parameters: %{
          type: "object",
          properties: %{
            task_id: %{type: "string", description: "ID of the task to update"},
            new_stage: %{type: "string", description: "New stage name"},
            stage_result: %{type: "object", description: "Result data from the current stage"}
          },
          required: ["task_id", "new_stage"]
        }
      },
      %{
        name: "create_assistant_message",
        description: "Create an assistant message in a chat session",
        parameters: %{
          type: "object",
          properties: %{
            session_id: %{type: "string", description: "Chat session ID"},
            content: %{type: "string", description: "Message content to send to the user"}
          },
          required: ["session_id", "content"]
        }
      },
      %{
        name: "create_system_notification",
        description: "Create a system notification for the user",
        parameters: %{
          type: "object",
          properties: %{
            title: %{type: "string", description: "Notification title"},
            message: %{type: "string", description: "Notification message content"},
            type: %{
              type: "string",
              enum: ["info", "success", "warning", "error"],
              description: "Type of notification"
            },
            metadata: %{type: "object", description: "Additional metadata for the notification"}
          },
          required: ["title", "message"]
        }
      },
      %{
        name: "wait_for_response",
        description: "Set a task to wait for external response (event-driven, no timeout)",
        parameters: %{
          type: "object",
          properties: %{
            task_id: %{type: "string", description: "ID of the task to set waiting"},
            wait_type: %{
              type: "string",
              enum: ["email", "meeting_response", "manual_input"],
              description: "Type of response to wait for"
            },
            thread_id: %{
              type: "string",
              description: "Email thread ID for email responses (optional)"
            },
            sender_email: %{
              type: "string",
              description: "Expected sender email for email responses (optional)"
            },
            response_type: %{type: "string", description: "Expected type of response (optional)"},
            context_update: %{type: "object", description: "Context data to update while waiting"}
          },
          required: ["task_id", "wait_type"]
        }
      }
    ]
  end




end
