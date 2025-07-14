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

    case Tasks.get_task(task_id) do
      {:ok, task} ->
        if task.user_id == user_id do
          previous_results = task.context["last_tool_results"] || []
          process_task(task, previous_results)
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
  defp process_task(task, tool_results \\ []) do
    if task.is_done do
      Logger.debug("[TaskExecutor] Task #{task.id} is already done")
      {:ok, :done}
    else
      Logger.debug("[TaskExecutor] Processing task #{task.id} with next_instruction: #{task.next_instruction}")
      context = build_task_context(task, tool_results)
      Logger.debug("[TaskExecutor] Calling AI for task #{task.id}")
      case call_ai_for_task(context) do
        {:ok, :tool_call, _updated_messages, tool_calls} ->
          Logger.debug("[TaskExecutor] AI returned #{length(tool_calls)} tool calls for task #{task.id}: #{inspect(tool_calls)}")
          results = execute_task_tool_calls(tool_calls, task)
          Logger.debug("[TaskExecutor] Tool execution results: #{inspect(results)}")
          should_halt = Enum.any?(tool_calls, fn tool_call -> tool_call["function"]["name"] in ["pause_task", "end_task"] end)
          Logger.debug("[TaskExecutor] Should halt: #{should_halt}")
          if should_halt do
            Logger.debug("[TaskExecutor] Halting task #{task.id}")
            {:ok, :halted}
          else
            {:ok, latest_task} = Tasks.get_task(task.id)
            serialized_results = Enum.map(results, fn 
              {:ok, res} -> %{"status" => "ok", "result" => res}
              {:error, reason} -> %{"status" => "error", "reason" => reason}
            end)
            new_context = Map.merge(latest_task.context || %{}, %{"last_tool_results" => serialized_results})
            {:ok, updated_task} = Tasks.update_task(latest_task, %{context: new_context})
            Logger.debug("[TaskExecutor] Updated task context with tool results for task #{updated_task.id}")
            Logger.debug("[TaskExecutor] Enqueuing next step for task #{updated_task.id}")
            {:ok, job} = TaskExecutor.new(%{"task_id" => updated_task.id, "user_id" => updated_task.user_id}) |> Oban.insert()
            Logger.debug("[TaskExecutor] Enqueued job #{job.id} for continued processing")
            {:ok, :continued}
          end
        {:ok, :message, _updated_messages, content} ->
          Logger.debug("[TaskExecutor] AI returned message: #{content}")
          {:ok, :halted}
        {:error, reason} ->
          Logger.error("[TaskExecutor] AI call failed for task #{task.id}: #{reason}")
          {:error, "Task AI processing failed: #{reason}"}
      end
    end
  end

  # Build context for task processing
  defp build_task_context(task, tool_results) do
    %{
      task: task,
      tool_results: tool_results,
      timestamp: DateTime.utc_now(),
      process_id: self(),
      node: Node.self()
    }
  end

  # Call AI with task execution capabilities
  defp call_ai_for_task(context) do
    prompt = build_task_prompt(context)
    Logger.debug("[TaskExecutor] Generated user prompt: #{prompt}")
    system_prompt = get_task_system_prompt()
    Logger.debug("[TaskExecutor] System prompt: #{system_prompt}")
    tool_definitions = get_task_tool_definitions() ++ ToolExecutor.get_tool_definitions()
    tools = OpenRouter.format_tools(tool_definitions)
    messages = [OpenRouter.user_message(prompt)]
    Logger.debug("[TaskExecutor] Calling OpenRouter with model #{@default_model}, tools: #{length(tools)}")
    result = OpenRouter.call_ai(@default_model, messages, tools: tools, system_prompt: system_prompt)
    Logger.debug("[TaskExecutor] AI result: #{inspect(result)}")
    result
  end

  # Execute tool calls for task processing
  defp execute_task_tool_calls(tool_calls, task) do
    Enum.map(tool_calls, fn tool_call ->
      tool_name = tool_call["function"]["name"]
      tool_args = Jason.decode!(tool_call["function"]["arguments"])
      execute_task_tool(tool_name, tool_args, task)
    end)
  end

  # Execute individual task tools
  defp execute_task_tool(tool_name, args, task) do
    case tool_name do
      "update_task" ->
        update_task_progress(task, args)

      "pause_task" ->
        pause_task(args, task)

      "end_task" ->
        end_task(args, task)

      "create_assistant_message" ->
        create_assistant_message(args, task.user_id)

      "create_system_message" ->
        create_system_message(args, task.user_id)

      _ ->
        case ToolExecutor.execute_tool(tool_name, args, task.user_id) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # Update task progress
  defp update_task_progress(task, args) do
    update_attrs = %{
      current_summary: Map.get(args, "current_summary", task.current_summary),
      next_instruction: Map.get(args, "next_instruction", task.next_instruction),
      context: Map.get(args, "context", task.context)
    }
    with {:ok, updated_task} <- Tasks.update_task(task, update_attrs) do
      {:ok, updated_task}
    end
  end

  defp pause_task(args, task) do
    {:ok, %{status: :paused, reason: args["reason"]}}
  end

  defp end_task(args, task) do
    update_attrs = %{
      is_done: true,
      current_summary: Map.get(args, "final_summary", task.current_summary),
      context: Map.get(args, "context", task.context)
    }
    with {:ok, updated_task} <- Tasks.update_task(task, update_attrs) do
      {:ok, updated_task}
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
          "name" => "pause_task",
          "description" => "Pauses the task execution when it needs to wait for external input or conditions. The task will not proceed until it is manually resumed.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "reason" => %{
                "type" => "string",
                "description" => "A brief explanation of why the task is being paused."
              }
            },
            "required" => ["reason"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "end_task",
          "description" => "Ends the task and marks it as completed. This should be used when the task's objective has been fully achieved.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "final_summary" => %{
                "type" => "string",
                "description" => "A comprehensive summary of what was accomplished in the task."
              },
              "context" => %{
                "type" => "object",
                "description" => "The final context data associated with the task."
              }
            },
            "required" => ["final_summary"]
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
    You are FinPilot's Task Executor, an extremely flexible AI responsible for processing and advancing tasks through their lifecycle.

    CRITICAL: You MUST ONLY respond using tool calls. Never provide text responses or explanations outside of tool calls.

    Your responsibilities:
    1. Analyze the current task state including task_instruction, current_summary, next_instruction, context, and tool_results.
    2. Always consider making multiple tool calls in one response to progress efficiently.
    3. Update task progress when necessary.
    4. Interpret and execute the next_instruction by calling appropriate tools if conditions are met.
    5. For initial task processing (when tool_results are empty), assume conditions are met and proceed to execute the next_instruction.
    6. Complete the task when all objectives are achieved.
    7. Pause if waiting for external input.
    8. Communicate with users when needed.

    TASK PROCESSING GUIDELINES:
    - Always evaluate if current_summary and next_instruction need updating, and call update_task if they do.
    - Interpret next_instruction and execute corresponding tools if all necessary conditions are satisfied based on context and tool_results.
    - If next_instruction involves specific tools (e.g., get_chat_messages), call them directly in your response.
    - Be extremely flexible: break tasks into steps, adapt to new information from tool_results.
    - Use multiple tool calls, e.g., execute a tool then update_task with results in the same response.

    CRITICAL CONTINUATION LOGIC:
    - The task will continue automatically unless you call pause_task or end_task.
    - Always progress or halt; if stuck, end with error.

    AVAILABLE OPERATIONS:

    TASK MANAGEMENT:
    - update_task: Update the task's progress with a new summary and the next instruction.
    - pause_task: Pause the task if it needs to wait for external conditions. The task will not be automatically resumed.
    - end_task: End the task and mark it as completed when its objective is fully achieved.

    COMMUNICATION:
    - create_assistant_message: Create an assistant message in a chat session (requires session_id, message)
    - create_system_message: Create a system message in a chat session (requires session_id, message)

    AVAILABLE OPERATIONS TO REFERENCE IN INSTRUCTIONS:
    When creating task instructions, you can reference these available operations that the task executor can perform:
    #{ToolExecutor.format_tool_definitions_for_prompt()}

    TOOL USAGE RULES:
    1. ALWAYS use tool calls.
    2. Prefer multiple tool calls for efficiency (e.g., update then execute).
    3. Call update_task before or after other actions if state needs updating.
    4. Execute tools directly if next_instruction requires it and conditions met.
    5. Use pause_task for external waits.
    6. Use end_task only when fully complete.
    7. Use communication tools for updates or questions.

    DECISION FLOW:
    1. Check if task is complete -> end_task.
    2. Check if needs pause -> pause_task.
    3. Evaluate next_instruction: if executable (especially if tool_results empty), call relevant tools and update_task if needed.
    4. If not executable, update_task with adjusted next_instruction.
    5. If no progress possible, end_task with error.
    6. Always aim for multiple calls if appropriate.

    ANTI-LOOP PROTECTION:
    - Detect repeated actions and end with error if stuck.
    - Vary approaches if previous tool_results indicate failure.

    Remember: Be flexible, use multiple tools per response when possible, and actively execute next_instructions.
    """
  end

  # Build AI prompt for task processing
  defp build_task_prompt(context) do
    task = context.task
    tool_results = context.tool_results

    """
    TASK TO PROCESS:
    Task ID: #{task.id}
    Task Instruction: #{task.task_instruction}
    Current Summary: #{task.current_summary || "No progress yet"}
    Next Instruction: #{task.next_instruction || "Not specified"}
    Is Done: #{task.is_done}
    Old Context: #{inspect(task.context || %{})}
    New Context (Tool Results): #{inspect(tool_results)}
    Created: #{task.inserted_at}
    Updated: #{task.updated_at}

    Analyze and progress the task flexibly.
    Remember to make multiple tool calls if needed, such as updating the task and executing next instruction if conditions met.
    """
  end

  # Create assistant message
  defp create_assistant_message(args, user_id) do
    message_params = %{
      user_id: user_id,
      role: "assistant",
      message: args["message"],
      session_id: args["session_id"]
    }
    with {:ok, message} <- ChatMessages.create_chat_message(message_params) do
      {:ok, %{message_id: message.id, content: message.message}}
    end
  end

  # Create system message
  defp create_system_message(args, user_id) do
    message_params = %{
      user_id: user_id,
      role: "system",
      message: args["message"],
      session_id: args["session_id"]
    }
    with {:ok, message} <- ChatMessages.create_chat_message(message_params) do
      {:ok, %{message_id: message.id, content: message.message}}
    end
  end

  # Format changeset errors
  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
