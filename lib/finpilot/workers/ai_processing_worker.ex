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

  alias FinpilotWeb.Structs.ProcessingContext
  alias Finpilot.Tasks.{Task, Instruction}
  alias Finpilot.Workers.TaskExecutor
  alias Finpilot.Workers.ToolExecutor
  alias Finpilot.Services.OpenRouter
  alias Finpilot.ChatMessages
  alias Finpilot.Repo
  import Ecto.Query

  # Default AI model for processing
  @default_model "google/gemini-2.0-flash-001"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"text" => text, "user_id" => user_id, "source" => source} = args
      }) do
    Logger.info("[AIProcessingWorker] Starting processing for user #{user_id} from source #{source}")
    Logger.debug("[AIProcessingWorker] Job args: #{inspect(args)}")

    user_id = ensure_binary_id(user_id)

    # Build context with instructions, running tasks, and metadata
    Logger.debug("[AIProcessingWorker] Building context for user #{user_id}")
    context = build_context(text, user_id, source, args)
    Logger.debug("[AIProcessingWorker] Context built with #{length(context.instructions)} instructions, #{length(context.running_tasks)} running tasks")

    # Call AI with direct tool calling
    Logger.info("[AIProcessingWorker] Calling AI with tools")
    case call_ai_with_tools(context) do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[AIProcessingWorker] AI returned #{length(tool_calls)} tool calls")
        Logger.debug("[AIProcessingWorker] Tool calls: #{inspect(tool_calls)}")
        result = execute_tool_calls(tool_calls, user_id, context)
        Logger.info("[AIProcessingWorker] Processing completed successfully")
        {:ok, result}
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI processing failed: #{reason}")
        {:error, "AI processing failed: #{reason}"}
    end
  end

  # Ensure user_id is in binary format
  defp ensure_binary_id(user_id) when is_binary(user_id), do: user_id
  defp ensure_binary_id(user_id), do: to_string(user_id)

  # Build comprehensive context for AI processing with enhanced metadata
  defp build_context(text, user_id, source, args) do
    instructions = get_active_instructions(user_id)
    running_tasks = get_running_tasks(user_id)
    session_id = args["session_id"]

    user_info = Finpilot.Accounts.get_user!(user_id)
    |> Map.take([:id, :name, :username, :email, :picture, :verified, :gmail_read, :gmail_write, :calendar_read, :calendar_write, :hubspot])

    %ProcessingContext{
      text: text,
      user_info: user_info,
      user_id: user_id,
      session_id: session_id,
      source: source,
      metadata: Map.drop(args, ["text", "user_id", "source", "session_id"]),
      instructions: instructions,
      running_tasks: running_tasks,
      history: args["history"] || [],
      timestamp: DateTime.utc_now(),
      process_id: self(),
      node: Node.self()
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
          where: t.user_id == ^user_id and t.is_done == false
        )
        |> Repo.all()
        |> Enum.map(fn task ->
          %{
            id: task.id,
            task_instruction: task.task_instruction,
            current_summary: task.current_summary,
            next_instruction: task.next_instruction,
            context: task.context
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



  # Call AI with direct tool calling
  defp call_ai_with_tools(context) do
    Logger.debug("[AIProcessingWorker] Building AI prompt for user #{context.user_id}")
    prompt = build_ai_prompt(context)
    Logger.debug("[AIProcessingWorker] Prompt length: #{String.length(prompt)} characters")

    Logger.debug("[AIProcessingWorker] Getting tool definitions")
    tool_definitions = get_tool_definitions()
    tools = OpenRouter.format_tools(tool_definitions)
    Logger.debug("[AIProcessingWorker] Using #{length(tools)} tools")

    history_messages = (context.history || []) |> Enum.map(fn msg ->
      %{role: msg["role"], content: msg["content"]}
    end)

    final_messages = history_messages ++ [OpenRouter.user_message(prompt)]

    Logger.info("[AIProcessingWorker] Calling OpenRouter AI with model #{@default_model}")
    result = case OpenRouter.call_ai(@default_model, final_messages,
      tools: tools,
      tool_choice: "required",
      system_prompt: get_system_prompt()
    ) do
      {:ok, :tool_call, updated_messages, tool_calls} ->
        Logger.info("[AIProcessingWorker] AI call successful, received #{length(tool_calls)} tool calls")
        {:ok, :tool_call, updated_messages, tool_calls}
      {:ok, :message, updated_messages} ->
        Logger.warning("[AIProcessingWorker] Unexpected message response when tool_choice is required, retrying with reminder")
        reminder = OpenRouter.system_message("REMINDER: You MUST respond ONLY with tool calls. Use create_assistant_message for any text responses.")
        retry_messages = updated_messages ++ [reminder]
        OpenRouter.call_ai(@default_model, retry_messages, tools: tools, tool_choice: "required", system_prompt: get_system_prompt())
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI call failed: #{reason}")
        {:error, reason}
      other ->
        Logger.warning("[AIProcessingWorker] Unexpected AI response: #{inspect(other)}")
        {:error, "Unexpected AI response"}
    end

    result
  end

  # Execute individual tool calls with better error handling
  defp execute_tool_calls(tool_calls, user_id, context) do
    Logger.info("[AIProcessingWorker] Executing #{length(tool_calls)} tool calls for user #{user_id}")

    Enum.with_index(tool_calls, 1)
    |> Enum.map(fn {tool_call, index} ->
      try do
        tool_name = tool_call["function"]["name"]
        tool_args = Jason.decode!(tool_call["function"]["arguments"])

        Logger.info("[AIProcessingWorker] Executing tool #{index}/#{length(tool_calls)}: #{tool_name} for user #{user_id}")
        Logger.debug("[AIProcessingWorker] Tool args: #{inspect(tool_args)}")

        case execute_tool(tool_name, tool_args, user_id, context) do
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
    You are FinPilot, an intelligent AI assistant that analyzes incoming text and orchestrates operations. You are designed to handle simple operations directly and delegate complex multi-step operations to tasks.

    CRITICAL RULES:
    1. You MUST ONLY respond using tool calls. Never provide text responses or explanations outside of tool calls.
    2. For general conversation or simple questions, use the `create_assistant_message` tool to respond directly.
    3. You can ONLY execute these tools directly: create_assistant_message, create_system_message, create_instruction, update_instruction, delete_instruction.
    4. For ALL OTHER operations (get_user_info, get_emails, search_emails, get_chat_messages, etc.), you MUST create a task that will handle the operation and provide results back to the user.
    5. Create tasks for ANY operation that involves data retrieval, external API calls, or multi-step processes.

    Your responsibilities:
    1. Analyze incoming text from various sources (chat, email, etc.).
    2. Respond to users directly for simple conversation.
    3. Create and manage user instructions.
    4. Create tasks for all data operations and complex workflows.

    CONTEXT SECTIONS:

    INCOMING TEXT:
    - Source: Origin of the text (chat, email, webhook, etc.)
    - Content: The actual message/text to process
    - Timestamp: When this processing request was made
    - Metadata: Additional context (session_id, etc.)

    ACTIVE INSTRUCTIONS:
    - User-defined automation rules and preferences
    - Persistent instructions that guide all decisions for this user
    - Use these to understand workflow preferences and automation triggers

    RUNNING TASKS:
    - Currently active, incomplete tasks
    - Shows: task ID, instruction, current summary, next instruction
    - Avoid duplicating work already in progress
    - Only create new tasks if they don't overlap with existing ones

    TASK CREATION GUIDELINES:
    - Create tasks for ANY operation that requires data retrieval (emails, user info, chat messages, etc.).
    - Create tasks for multi-step processes, calculations, or operations that need to process results.
    - Tasks will handle the complexity and provide results back to the user automatically.
    - When creating tasks, be specific about what the task should accomplish and how it should respond to the user.

    AVAILABLE TOOLS:
    You can use the following tools directly. For long-running processes, you can create a task that uses these tools.
    #{format_all_tool_definitions_for_prompt()}

    TOOL USAGE RULES:
    1. ALWAYS use tool calls - never respond with plain text
    2. Use create_assistant_message ONLY for simple conversation and immediate responses
    3. Use create_system_message for internal logging and system communications
    4. Use create_instruction, update_instruction, delete_instruction for managing user automation rules
    5. Use create_task for ALL data operations (emails, user info, chat messages, etc.)
    6. Use create_task for ANY multi-step process or operation that needs to process results
    7. Be proactive in identifying ALL actionable items from incoming text
    8. Consider context from running tasks and user instructions
    9. If user requests invalid operations, use create_assistant_message to explain limitations

    DECISION FLOW:
    1. Analyze the incoming text and determine the user's intent.
    2. If it's simple conversation without data needs, use `create_assistant_message`.
    3. If it involves managing instructions, use the appropriate instruction tools.
    4. For ANY data retrieval or complex operation, create a task with specific instructions.
    5. When creating tasks, include clear instructions on how the task should respond to the user.
    6. Tasks will automatically handle multi-step operations and provide results back to users.

    INSTRUCTION HANDLING:
    - Analyze incoming text for potential instructions, especially persistent or long-running ones (e.g., "Whenever I get an email, do X")
    - Use create_instruction to add new persistent instructions
    - Use update_instruction to modify existing ones
    - Use delete_instruction to remove them
    - When source is 'chat', ALWAYS include a create_assistant_message tool call to provide a response to the user, in addition to any other tool calls.
    - For instructions, create or update them first, then send a confirmation message.

    CONTEXTUAL AWARENESS:
    - You have access to a `context` object that contains `user_id`, `source`, `metadata`, etc.
    - When a tool requires a `user_id` or `session_id`, you should be able to infer it from the context provided in the prompt.
    - Do not ask for information that is already available in the context.

    TASK DELEGATION STRATEGY:
    - You are a simple orchestrator that delegates complex work to tasks
    - Tasks have access to all the tools you see in the available tools list
    - Tasks can execute multiple tools, process results, and make decisions
    - Tasks will automatically communicate results back to users
    - Your job is to create well-defined tasks with clear objectives

    Remember: You are a simple orchestrator. Delegate complex operations to tasks and handle only basic communication and instruction management directly.
    """
  end

  # Build AI prompt with context
  defp build_ai_prompt(context) do
    instructions_text = format_instructions(context.instructions)
    tasks_text = format_running_tasks(context.running_tasks)

    """
      INCOMING TEXT:
      User ID: #{context.user_id}
      Source: #{context.source}
      Content: #{context.text}
      Timestamp: #{context.timestamp}

      USER_INFORMATION:
      #{inspect(context.user_info)}

      #{if context.metadata != %{}, do: "Metadata: #{inspect(context.metadata)}\n", else: ""}

      ACTIVE INSTRUCTIONS:
      #{instructions_text}

      RUNNING TASKS:
      #{tasks_text}

      RAW_CONTEXT:
      #{inspect(context)}

      Please analyze this incoming text and respond appropriately using tool calls for actions or direct messages for communication.
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
      Current Summary: #{task.current_summary || "Not started"}
      Next Instruction: #{task.next_instruction || "None"}
      """
    end)
    |> Enum.join("\n---\n")
  end



  # Get tool definitions for AI processing
  def get_tool_definitions do
    # Only include tools that AI processing worker can execute directly
    ai_processing_tools = [
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_task",
          "description" => "Create a new task for tool calling and multi step tool calling process",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "task_instruction" => %{
                "type" => "string",
                "description" => "Detailed instruction describing what the task should achieve to be considered complete"
              },
              "current_summary" => %{
                "type" => "string",
                "description" => "Summary of what has been done so far (initially just the starting summary)",
                "default" => ""
              },
              "next_instruction" => %{
                "type" => "string",
                "description" => "Specific instruction for what the AI should do when processing this task next"
              },
              "context" => %{
                "type" => "object",
                "description" => "Additional context and metadata for the task",
                "default" => %{}
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Optional chat session ID to associate the task with"
              }
            },
            "required" => ["task_instruction", "next_instruction"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_instruction",
          "description" => "Create a new persistent instruction for the user",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{
                "type" => "string",
                "description" => "Name of the instruction"
              },
              "description" => %{
                "type" => "string",
                "description" => "Description of the instruction"
              },
              "trigger_conditions" => %{
                "type" => "object",
                "description" => "Conditions that trigger this instruction as a JSON object"
              },
              "actions" => %{
                "type" => "object",
                "description" => "Actions to perform when triggered as a JSON object"
              },
              "ai_prompt" => %{
                "type" => "string",
                "description" => "AI prompt for this instruction"
              }
            },
            "required" => ["name", "description", "trigger_conditions", "actions", "ai_prompt"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "update_instruction",
          "description" => "Update an existing instruction",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{
                "type" => "string",
                "description" => "ID of the instruction to update"
              },
              "name" => %{
                "type" => "string",
                "description" => "New name"
              },
              "description" => %{
                "type" => "string",
                "description" => "New description"
              },
              "trigger_conditions" => %{
                "type" => "string",
                "description" => "New trigger conditions"
              },
              "actions" => %{
                "type" => "string",
                "description" => "New actions"
              },
              "ai_prompt" => %{
                "type" => "string",
                "description" => "New AI prompt"
              },
              "is_active" => %{
                "type" => "boolean",
                "description" => "Active status"
              }
            },
            "required" => ["id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "delete_instruction",
          "description" => "Delete an existing instruction",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{
                "type" => "string",
                "description" => "ID of the instruction to delete"
              }
            },
            "required" => ["id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_assistant_message",
          "description" => "Send a message to the user as the AI assistant",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "message" => %{
                "type" => "string",
                "description" => "The message content to send to the user"
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Required chat session ID to associate the message with"
              }
            },
            "required" => ["message", "session_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_system_message",
          "description" => "Create a system message for logging or internal communication",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "message" => %{
                "type" => "string",
                "description" => "The system message content"
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Optional chat session ID to associate the message with"
              }
            },
            "required" => ["message"]
          }
        }
      }
    ]

    # Return only AI processing tools - tasks will handle ToolExecutor tools
    ai_processing_tools
  end

  # Format all tool definitions for the AI prompt
  defp format_all_tool_definitions_for_prompt do
    # Get the ToolExecutor formatted definitions for task reference
    tool_executor_definitions = ToolExecutor.format_tool_definitions_for_prompt()

    # Add AI processing specific tools
    ai_processing_definitions = """

    TOOLS YOU CAN EXECUTE DIRECTLY:

    5. create_assistant_message
       - Description: Send a message to the user as the AI assistant
       - Required: message (string), session_id (string)
       - Returns: Message ID and content

    6. create_system_message
       - Description: Create a system message for logging or internal communication
       - Required: message (string)
       - Optional: session_id (string)
       - Returns: Message ID and content

    7. create_instruction
       - Description: Create a new persistent instruction for the user
       - Required: name (string), description (string), trigger_conditions (object), actions (object), ai_prompt (string)
       - Returns: Instruction ID

    8. update_instruction
       - Description: Update an existing instruction
       - Required: id (string)
       - Optional: name, description, trigger_conditions, actions, ai_prompt, is_active
       - Returns: Instruction ID

    9. delete_instruction
       - Description: Delete an existing instruction
       - Required: id (string)
       - Returns: Instruction ID

    10. create_task
        - Description: Create a new task that can use any of the tools listed above in "Available Tools" section
        - Required: task_instruction (string), next_instruction (string)
        - Optional: current_summary (string), context (object), session_id (string)
        - Returns: Task ID, job ID, current summary, and confirmation message
        - Note: Tasks can execute multiple tools, process results, and communicate with users automatically
    """

    "TOOLS AVAILABLE FOR TASKS TO USE:\n\n" <> tool_executor_definitions <> "\n" <> ai_processing_definitions
  end

  defp execute_tool("create_instruction", args, user_id, _context) do
    Logger.info("[AIProcessingWorker] Creating instruction for user #{user_id}")

    instruction_params = %{
      user_id: user_id,
      name: args["name"],
      description: args["description"],
      trigger_conditions: args["trigger_conditions"],
      actions: args["actions"],
      ai_prompt: args["ai_prompt"],
      is_active: true
    }

    case Finpilot.Tasks.create_instruction(instruction_params) do
      {:ok, instruction} ->
        Logger.info("[AIProcessingWorker] Instruction created: #{instruction.id}")
        {:ok, %{instruction_id: instruction.id}}
      {:error, changeset} ->
        error_msg = "Failed to create instruction: #{inspect(changeset.errors)}"
        Logger.error("[AIProcessingWorker] #{error_msg}")
        create_error_system_message(user_id, error_msg, args["session_id"])
        {:error, error_msg}
    end
  end

  defp execute_tool("update_instruction", args, user_id, _context) do
    Logger.info("[AIProcessingWorker] Updating instruction #{args["id"]} for user #{user_id}")

    try do
  instruction = Finpilot.Tasks.get_instruction!(args["id"])
  update_params = Map.take(args, ["name", "description", "trigger_conditions", "actions", "ai_prompt", "is_active"])
  case Finpilot.Tasks.update_instruction(instruction, update_params) do
    {:ok, updated} ->
      Logger.info("[AIProcessingWorker] Instruction updated: #{updated.id}")
      {:ok, %{instruction_id: updated.id}}
    {:error, changeset} ->
      error_msg = "Failed to update instruction: #{inspect(changeset.errors)}"
      Logger.error("[AIProcessingWorker] #{error_msg}")
      create_error_system_message(user_id, error_msg, args["session_id"])
      {:error, error_msg}
  end
rescue
  Ecto.NoResultsError -> {:error, "Instruction not found"}
end
end

  defp execute_tool("delete_instruction", args, user_id, _context) do
    Logger.info("[AIProcessingWorker] Deleting instruction #{args["id"]} for user #{user_id}")

    try do
  instruction = Finpilot.Tasks.get_instruction!(args["id"])
  case Finpilot.Tasks.delete_instruction(instruction) do
    {:ok, _} ->
      Logger.info("[AIProcessingWorker] Instruction deleted: #{args["id"]}")
      {:ok, %{instruction_id: args["id"]}}
    {:error, reason} ->
      Logger.error("[AIProcessingWorker] Failed to delete instruction: #{inspect(reason)}")
      {:error, "Failed to delete instruction"}
  end
rescue
  Ecto.NoResultsError -> {:error, "Instruction not found"}
end
end

  # Execute tool calls locally
  defp execute_tool("create_task", args, user_id, context) do
    Logger.info("[AIProcessingWorker] Creating task for user #{user_id}")

    # Ensure current_summary is not blank
    current_summary = case args["current_summary"] do
      nil -> "Task created and ready to begin"
      "" -> "Task created and ready to begin"
      summary when is_binary(summary) ->
        trimmed = String.trim(summary)
        if byte_size(trimmed) > 0, do: summary, else: "Task created and ready to begin"
      _ -> "Task created and ready to begin"
    end

    # Use the provided context or extract session_id from the original context
    # Priority: explicit session_id parameter > context.session_id > existing context
    session_id = args["session_id"] || context.session_id
    
    task_context = args["context"] || %{}
    # Ensure session_id is included in context if provided
    task_context = if session_id, do: Map.put(task_context, "session_id", session_id), else: task_context

    task_params = %{
      user_id: user_id,
      task_instruction: args["task_instruction"] || "",
      current_summary: current_summary,
      next_instruction: args["next_instruction"] || "",
      context: task_context,
      session_id: session_id,
      is_done: false
    }

    case Finpilot.Tasks.create_task(task_params) do
      {:ok, task} ->
        Logger.info("[AIProcessingWorker] Task created successfully: #{task.id}")

        # Enqueue the task for execution
        case TaskExecutor.new(%{"task_id" => task.id, "user_id" => user_id}) |> Oban.insert() do
          {:ok, job} ->
            Logger.info("[AIProcessingWorker] Task execution job enqueued: #{job.id}")
            {:ok, %{task_id: task.id, job_id: job.id, current_summary: task.current_summary, message: "Task created and execution started"}}
          {:error, reason} ->
            Logger.error("[AIProcessingWorker] Failed to enqueue task execution: #{reason}")
            # Create system message about the error
            create_error_system_message(user_id, "Failed to start task execution: #{reason}", args["session_id"])
            {:error, "Failed to start task execution: #{reason}"}
        end

      {:error, changeset} ->
        error_msg = "Failed to create task: #{inspect(changeset.errors)}"
        Logger.error("[AIProcessingWorker] #{error_msg}")
        # Create system message about the error
        create_error_system_message(user_id, error_msg, args["session_id"])
        {:error, error_msg}
    end
  end

  defp execute_tool("create_assistant_message", args, user_id, _context) do
    Logger.info("[AIProcessingWorker] Creating assistant message for user #{user_id}")

    message_params = %{
      user_id: user_id,
      role: "assistant",
      message: args["message"],
      session_id: args["session_id"]
    }

    case ChatMessages.create_chat_message(message_params) do
      {:ok, message} ->
        Logger.info("[AIProcessingWorker] Assistant message created: #{message.id}")
        {:ok, %{message_id: message.id, content: message.message}}
      {:error, changeset} ->
        Logger.error("[AIProcessingWorker] Failed to create assistant message: #{inspect(changeset.errors)}")
        {:error, "Failed to create message: #{inspect(changeset.errors)}"}
    end
  end

  defp execute_tool("create_system_message", args, user_id, _context) do
    Logger.info("[AIProcessingWorker] Creating system message for user #{user_id}")

    message_params = %{
      user_id: user_id,
      role: "system",
      message: args["message"],
      session_id: args["session_id"]
    }

    case ChatMessages.create_chat_message(message_params) do
      {:ok, message} ->
        Logger.info("[AIProcessingWorker] System message created: #{message.id}")
        {:ok, %{message_id: message.id, content: message.message}}
      {:error, changeset} ->
        Logger.error("[AIProcessingWorker] Failed to create system message: #{inspect(changeset.errors)}")
        {:error, "Failed to create message: #{inspect(changeset.errors)}"}
    end
  end

  defp execute_tool(tool_name, args, user_id, _context) do
    Logger.error("[AIProcessingWorker] Unknown tool: #{tool_name} for user #{user_id}")
    create_error_system_message(user_id, "Unknown tool: #{tool_name}", args["session_id"])
    {:error, "Unknown tool: #{tool_name}"}
  end

  # Helper function to create system messages for errors
  defp create_error_system_message(user_id, error_message, session_id) do
    message_params = %{
      user_id: user_id,
      role: "system",
      message: "Error: #{error_message}",
      session_id: session_id
    }

    case ChatMessages.create_chat_message(message_params) do
      {:ok, _message} ->
        Logger.info("[AIProcessingWorker] Error system message created for user #{user_id}")
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] Failed to create error system message: #{inspect(reason)}")
    end
  end

end
