defmodule Finpilot.Workers.TaskExecutor do
  @moduledoc """
  Oban worker for executing and updating tasks through AI analysis.
  This worker:
  1. Takes a task and processes it using AI
  2. Updates the task's current_summary and next_instruction
  3. Executes tools based on AI decisions for task progression
  4. Handles task completion when appropriate
  """

  use Oban.Worker, queue: :task_execution
  require Logger

  alias Finpilot.Tasks
  alias Finpilot.ChatMessages
  alias Finpilot.Services.OpenRouter
  alias Finpilot.Workers.ToolExecutor

  # Default AI model for task processing
  @default_model "google/gemini-2.0-flash-001"

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: job_id,
        args: %{"task_id" => task_id, "user_id" => user_id} = args
      }) do
    Logger.info("[TaskExecutor] Starting job #{job_id} for task #{task_id} and user #{user_id}")
    Logger.debug("[TaskExecutor] Job args: #{inspect(args)}")

    user_id = ensure_binary_id(user_id)

    # Get the task
    case Tasks.get_task(task_id) do
      {:ok, task} ->
        if task.user_id == user_id do
          process_task(task, job_id)
        else
          Logger.error("[TaskExecutor] Task #{task_id} does not belong to user #{user_id}")
          {:error, "Task not found or access denied"}
        end

      {:error, :not_found} ->
        Logger.error("[TaskExecutor] Task #{task_id} not found")
        {:error, "Task not found"}
    end
  end

  # Ensure user_id is in binary format
  defp ensure_binary_id(user_id) when is_binary(user_id), do: user_id
  defp ensure_binary_id(user_id), do: to_string(user_id)

  # Process the task using AI
  defp process_task(task, job_id) do
    Logger.info("[TaskExecutor] Processing task #{task.id} for job #{job_id}")

    # Build context for AI processing
    context = build_task_context(task, job_id)
    Logger.debug("[TaskExecutor] Context built for task #{task.id}")

    # Call AI with task execution tools
    Logger.info("[TaskExecutor] Calling AI for task #{task.id}")
    case call_ai_for_task(context) do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[TaskExecutor] AI returned #{length(tool_calls)} tool calls for task #{task.id}")
        Logger.debug("[TaskExecutor] Tool calls: #{inspect(tool_calls)}")
        result = execute_task_tool_calls(tool_calls, task)
        Logger.info("[TaskExecutor] Task #{task.id} processing completed")
        {:ok, result}

      {:error, reason} ->
        Logger.error("[TaskExecutor] AI processing failed for task #{task.id}: #{reason}")
        {:error, "Task AI processing failed: #{reason}"}
    end
  end

  # Build context for task processing
  defp build_task_context(task, job_id) do
    %{
      task: task,
      timestamp: DateTime.utc_now(),
      process_id: self(),
      node: Node.self(),
      job_id: job_id
    }
  end

  # Call AI with task execution capabilities
  defp call_ai_for_task(context) do
    Logger.debug("[TaskExecutor] Building AI prompt for task #{context.task.id}")
    prompt = build_task_prompt(context)
    Logger.debug("[TaskExecutor] Prompt length: #{String.length(prompt)} characters")

    Logger.debug("[TaskExecutor] Getting task execution tool definitions")
    tool_definitions = get_task_tool_definitions()
    tools = OpenRouter.format_tools(tool_definitions)
    Logger.debug("[TaskExecutor] Using #{length(tools)} tools")

    messages = [OpenRouter.user_message(prompt)]

    Logger.info("[TaskExecutor] Calling OpenRouter AI with model #{@default_model}")
    result = OpenRouter.call_ai(@default_model, messages,
      tools: tools,
      system_prompt: get_task_system_prompt()
    )

    case result do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info("[TaskExecutor] AI call successful, received #{length(tool_calls)} tool calls")
      {:error, reason} ->
        Logger.error("[TaskExecutor] AI call failed: #{reason}")
      other ->
        Logger.warning("[TaskExecutor] Unexpected AI response: #{inspect(other)}")
    end

    result
  end

  # Execute tool calls for task processing
  defp execute_task_tool_calls(tool_calls, task) do
    Logger.info("[TaskExecutor] Executing #{length(tool_calls)} tool calls for task #{task.id}")

    results = Enum.with_index(tool_calls, 1)
    |> Enum.map(fn {tool_call, index} ->
      try do
        tool_name = tool_call["function"]["name"]
        tool_args = Jason.decode!(tool_call["function"]["arguments"])

        Logger.info("[TaskExecutor] Executing tool #{index}/#{length(tool_calls)}: #{tool_name} for task #{task.id}")
        Logger.debug("[TaskExecutor] Tool args: #{inspect(tool_args)}")

        case execute_task_tool(tool_name, tool_args, task) do
          {:ok, result} ->
            Logger.info("[TaskExecutor] Tool #{tool_name} executed successfully for task #{task.id}")
            Logger.debug("[TaskExecutor] Tool result: #{inspect(result)}")
            {:ok, result}

          {:error, reason} ->
            Logger.error("[TaskExecutor] Tool #{tool_name} failed for task #{task.id}: #{reason}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("[TaskExecutor] Tool execution exception for task #{task.id}: #{inspect(e)}")
          Logger.error("[TaskExecutor] Tool call that caused exception: #{inspect(tool_call)}")
          {:error, "Tool execution exception: #{inspect(e)}"}
      end
    end)

    # Check if any tool call requested continuation
    should_continue = Enum.any?(tool_calls, fn tool_call ->
      tool_call["function"]["name"] == "continue_task_execution"
    end)

    if should_continue do
      Logger.info("[TaskExecutor] Continuing task execution for task #{task.id}")
      continue_task_execution(task)
    else
      results
    end
  end

  # Execute individual task tools
  defp execute_task_tool(tool_name, args, task) do
    case tool_name do
      "update_task" -> update_task_progress(args, task)
      "complete_task" -> complete_task(args, task)
      "create_assistant_message" -> create_assistant_message(args, task.user_id)
      "create_system_message" -> create_system_message(args, task.user_id)
      "continue_task_execution" -> {:ok, "Task execution will continue"}
      "search_tasks" -> execute_search_tool("search_tasks", args, task)
      "search_chat_messages" -> execute_search_tool("search_chat_messages", args, task)
      "find_relevant_context" -> execute_search_tool("find_relevant_context", args, task)
      _ -> {:error, "Unknown task tool: #{tool_name}"}
    end
  end

  # Execute search and memory tools
  defp execute_search_tool(tool_name, args, task) do
    Logger.info("[TaskExecutor] Executing search tool #{tool_name} for task #{task.id}")
    
    case ToolExecutor.execute_tool(tool_name, args, task.user_id) do
      {:ok, results} ->
        Logger.info("[TaskExecutor] Search tool #{tool_name} executed successfully for task #{task.id}")
        # Update task context with search results
        updated_context = Map.put(task.context || %{}, "#{tool_name}_results", results)
        
        # Update task with search results in context
         result_count = case results do
           results when is_list(results) -> length(results)
           %{tasks: tasks, messages: messages} -> length(tasks) + length(messages)
           _ -> "some"
         end
         
         update_attrs = %{
           "context" => updated_context,
           "current_summary" => "#{task.current_summary || ""} Executed #{tool_name} and found #{result_count} results."
         }
        
        case Tasks.update_task(task, update_attrs) do
          {:ok, updated_task} ->
            Logger.info("[TaskExecutor] Task #{task.id} updated with search results")
            {:ok, %{results: results, updated_task: updated_task}}
          {:error, changeset} ->
            Logger.error("[TaskExecutor] Failed to update task with search results: #{inspect(changeset.errors)}")
            {:error, "Failed to update task: #{format_changeset_errors(changeset)}"}
        end
        
      {:error, reason} ->
        Logger.error("[TaskExecutor] Search tool #{tool_name} failed for task #{task.id}: #{reason}")
        {:error, "Search operation failed: #{reason}"}
    end
  end

  # Continue task execution recursively
  defp continue_task_execution(task) do
    Logger.info("[TaskExecutor] Starting recursive execution for task #{task.id}")
    
    # Get the updated task from database to ensure we have latest state
    case Tasks.get_task(task.id) do
      {:ok, updated_task} ->
        if updated_task.is_done do
          Logger.info("[TaskExecutor] Task #{task.id} is already completed, stopping recursion")
          {:ok, "Task completed"}
        else
          # Build new context and continue processing
          context = build_task_context(updated_task, "recursive_#{System.unique_integer()}")
          
          case call_ai_for_task(context) do
            {:ok, :tool_call, _updated_messages, tool_calls} ->
              Logger.info("[TaskExecutor] Recursive AI call returned #{length(tool_calls)} tool calls for task #{task.id}")
              execute_task_tool_calls(tool_calls, updated_task)
              
            {:error, reason} ->
              Logger.error("[TaskExecutor] Recursive AI processing failed for task #{task.id}: #{reason}")
              {:error, "Recursive task AI processing failed: #{reason}"}
          end
        end
        
      {:error, :not_found} ->
        Logger.error("[TaskExecutor] Task #{task.id} not found during recursive execution")
        {:error, "Task not found"}
    end
  end

  # Update task progress
  defp update_task_progress(args, task) do
    update_attrs = %{
      "current_summary" => Map.get(args, "current_summary", task.current_summary),
      "next_instruction" => Map.get(args, "next_instruction", task.next_instruction),
      "context" => Map.get(args, "context", task.context)
    }

    case Tasks.update_task(task, update_attrs) do
      {:ok, updated_task} ->
        Logger.info("[TaskExecutor] Successfully updated task: #{task.id}")
        {:ok, updated_task}
      {:error, changeset} ->
        Logger.error("[TaskExecutor] Failed to update task: #{inspect(changeset.errors)}")
        {:error, "Failed to update task: #{format_changeset_errors(changeset)}"}
    end
  end

  # Complete task
  defp complete_task(args, task) do
    update_attrs = %{
      "is_done" => true,
      "current_summary" => Map.get(args, "final_summary", task.current_summary),
      "context" => Map.get(args, "context", task.context)
    }

    case Tasks.update_task(task, update_attrs) do
      {:ok, updated_task} ->
        Logger.info("[TaskExecutor] Successfully completed task: #{task.id}")
        {:ok, updated_task}
      {:error, changeset} ->
        Logger.error("[TaskExecutor] Failed to complete task: #{inspect(changeset.errors)}")
        {:error, "Failed to complete task: #{format_changeset_errors(changeset)}"}
    end
  end

  # Get tool definitions for task execution
  defp get_task_tool_definitions do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "update_task",
          "description" => "Update the task's progress with new summary and next instruction",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "current_summary" => %{
                "type" => "string",
                "description" => "Updated summary of what has been accomplished so far"
              },
              "next_instruction" => %{
                "type" => "string",
                "description" => "What should be done next to progress the task"
              },
              "context" => %{
                "type" => "object",
                "description" => "Updated context data for the task"
              }
            },
            "required" => ["current_summary", "next_instruction"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "complete_task",
          "description" => "Mark the task as completed",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "final_summary" => %{
                "type" => "string",
                "description" => "Final summary of what was accomplished"
              },
              "context" => %{
                "type" => "object",
                "description" => "Final context data for the task"
              }
            },
            "required" => ["final_summary"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "continue_task_execution",
          "description" => "Continue executing the task immediately if the next instruction can be executed right away. Use this when the task can progress without waiting for external conditions or user input.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "reason" => %{
                "type" => "string",
                "description" => "Reason why the task execution should continue immediately"
              }
            },
            "required" => ["reason"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_assistant_message",
          "description" => "Create an assistant message in a chat session",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "session_id" => %{
                "type" => "string",
                "description" => "The ID of the chat session"
              },
              "message" => %{
                "type" => "string",
                "description" => "The message content from the assistant"
              }
            },
            "required" => ["session_id", "message"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_system_message",
          "description" => "Create a system message in a chat session",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "session_id" => %{
                "type" => "string",
                "description" => "The ID of the chat session"
              },
              "message" => %{
                "type" => "string",
                "description" => "The system message content"
              }
            },
            "required" => ["session_id", "message"]
          }
        }
      }
    ]
  end

  # Get system prompt for task execution
  defp get_task_system_prompt do
    """
    You are FinPilot's Task Executor, responsible for processing and advancing individual tasks through their lifecycle.

    CRITICAL: You MUST ONLY respond using tool calls. Never provide text responses or explanations outside of tool calls.

    Your responsibilities:
    1. Analyze the current task state and determine next actions
    2. Update task progress with current_summary and next_instruction
    3. Execute specific actions needed to advance the task
    4. Complete tasks when all objectives are achieved
    5. Communicate with users about task progress
    6. Continue task execution recursively when possible

    TASK PROCESSING GUIDELINES:
    - current_summary: Detailed summary of what has been accomplished so far
    - next_instruction: Specific instruction for what should be done next
    - Always update both fields when progressing a task
    - Only complete a task when all objectives in task_instruction are fully achieved
    - Break complex tasks into smaller, manageable steps
    - Be specific and actionable in next_instruction

    AVAILABLE OPERATIONS FOR TASK INSTRUCTIONS:
    When creating next_instruction, you can only reference these available operations:
    
    TASK MANAGEMENT:
    - update_task: Update the task's progress with new summary and next instruction (requires current_summary, next_instruction)
    - complete_task: Mark the task as completed (requires final_summary)
    - continue_task_execution: Continue executing the task immediately if next step can be executed right away (requires reason)
    
    COMMUNICATION:
    - create_assistant_message: Create an assistant message in a chat session (requires session_id, message)
    - create_system_message: Create a system message in a chat session (requires session_id, message)
    
    SEARCH AND MEMORY:
    - search_tasks: Search for similar tasks based on semantic similarity (requires query)
    - search_chat_messages: Search for similar chat messages based on semantic similarity (requires query)
    - find_relevant_context: Find relevant context by searching both tasks and chat messages (requires query)



    RECURSIVE EXECUTION:
    - Use continue_task_execution when the next step can be executed immediately
    - Continue execution when no external dependencies or waiting is required
    - Do NOT continue if waiting for user input, external systems, or time-based conditions
    - The system will automatically re-evaluate the task and continue processing
    - This allows for autonomous task progression without manual intervention

    TOOL USAGE RULES:
    1. ALWAYS use tool calls - never respond with plain text
    2. Use update_task to progress the task with new summary and next instruction
    3. Use complete_task only when the task_instruction is fully satisfied
    4. Use continue_task_execution to immediately continue processing if next step is ready
    5. Use assistant_message to communicate progress or ask for clarification
    6. Use system_message for important status updates
    7. Be thorough in documenting progress in current_summary
    8. Be specific and actionable in next_instruction
    9. Use your judgment to determine appropriate operations and next steps based on task requirements

    DECISION FLOW:
    1. If task is complete -> use complete_task
    2. If next step requires waiting/external input -> use update_task only
    3. If next step can be executed immediately -> use update_task + continue_task_execution
    4. If need to communicate with user -> use assistant_message or system_message
    5. If need to determine next steps -> analyze task requirements and set appropriate next_instruction

    Remember: Every response must be a tool call. Focus on advancing the task toward completion autonomously when possible.
    """
  end

  # Build AI prompt for task processing
  defp build_task_prompt(context) do
    task = context.task

    """
    TASK TO PROCESS:
    Task ID: #{task.id}
    Task Instruction: #{task.task_instruction}
    Current Summary: #{task.current_summary || "No progress yet"}
    Next Instruction: #{task.next_instruction || "Not specified"}
    Is Done: #{task.is_done}
    Context: #{inspect(task.context || %{})}
    Created: #{task.inserted_at}
    Updated: #{task.updated_at}

    Please analyze this task and determine the appropriate next action.

    DECISION LOGIC:
    1. If the task is fully complete according to task_instruction -> use complete_task
    2. If the task needs progression:
       a. Use update_task to record progress and set next_instruction
       b. If the next_instruction can be executed immediately (no waiting required) -> ALSO use continue_task_execution
       c. If the next_instruction requires waiting for external input/conditions -> use update_task ONLY
    3. If you need to communicate with the user -> use assistant_message or system_message

    RECURSIVE EXECUTION GUIDELINES:
    - Use continue_task_execution when the next step is actionable immediately
    - Examples of when to continue: data processing, calculations, analysis, planning next steps
    - Examples of when NOT to continue: waiting for user input, external API responses, file uploads, scheduled events
    - The system will re-evaluate the updated task and continue processing automatically
    - This enables autonomous task completion without manual intervention

    Remember: You can use multiple tools in one response. For example, update_task + continue_task_execution to progress and continue immediately.
    """
  end

  # Create assistant message
  defp create_assistant_message(args, user_id) do
    Logger.info("[TaskExecutor] Creating assistant message for user #{user_id}")

    message_params = %{
      user_id: user_id,
      role: "assistant",
      message: args["message"],
      session_id: args["session_id"]
    }

    case ChatMessages.create_chat_message(message_params) do
      {:ok, message} ->
        Logger.info("[TaskExecutor] Successfully created assistant message: #{message.id}")
        {:ok, %{message_id: message.id, content: message.message}}
      {:error, changeset} ->
        Logger.error("[TaskExecutor] Failed to create assistant message: #{inspect(changeset.errors)}")
        {:error, "Failed to create message: #{inspect(changeset.errors)}"}
    end
  end

  # Create system message
  defp create_system_message(args, user_id) do
    Logger.info("[TaskExecutor] Creating system message for user #{user_id}")

    message_params = %{
      user_id: user_id,
      role: "system",
      message: args["message"],
      session_id: args["session_id"]
    }

    case ChatMessages.create_chat_message(message_params) do
      {:ok, message} ->
        Logger.info("[TaskExecutor] Successfully created system message: #{message.id}")
        {:ok, %{message_id: message.id, content: message.message}}
      {:error, changeset} ->
        Logger.error("[TaskExecutor] Failed to create system message: #{inspect(changeset.errors)}")
        {:error, "Failed to create message: #{inspect(changeset.errors)}"}
    end
  end



  # Format changeset errors
  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
