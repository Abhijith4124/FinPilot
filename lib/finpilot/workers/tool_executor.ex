defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools within the Tasks system.
  This module provides a centralized way to execute various tools
  that the AI can call to complete tasks and manage chat messages.
  """

  require Logger
  alias Finpilot.Tasks
  alias Finpilot.ChatMessages

  @doc """
  Execute a tool with the given name, arguments, and user context.
  
  ## Examples
  
      iex> ToolExecutor.execute_tool("create_task", %{"task_instruction" => "Send email"}, user_id)
      {:ok, %Task{}}
      
      iex> ToolExecutor.execute_tool("create_assistant_message", %{"session_id" => "123", "message" => "Hello"}, user_id)
      {:ok, %ChatMessage{}}
      
      iex> ToolExecutor.execute_tool("create_system_message", %{"session_id" => "123", "message" => "System ready"}, user_id)
      {:ok, %ChatMessage{}}
  """
  def execute_tool(tool_name, args, user_id) do
    case tool_name do
      "create_assistant_message" -> create_assistant_message(args, user_id)
      "create_system_message" -> create_system_message(args, user_id)
      "create_task" -> create_task(args, user_id)
      "edit_task" -> edit_task(args, user_id)
      "create_task_stage" -> create_task_stage(args, user_id)
      "edit_task_stage" -> edit_task_stage(args, user_id)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end

  @doc """
  Returns tool definitions for LLM integration.
  These definitions can be used with OpenRouter or other LLM providers.
  """
  def tool_definitions do
    [
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
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_task",
          "description" => "Create a new task for the user",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "task_instruction" => %{
                "type" => "string",
                "description" => "The main instruction or description of the task"
              },
              "current_stage_summary" => %{
                "type" => "string",
                "description" => "Summary of the current stage of the task"
              },
              "next_stage_instruction" => %{
                "type" => "string",
                "description" => "Instruction for the next stage of the task"
              },
              "context" => %{
                "type" => "object",
                "description" => "Additional context data for the task"
              }
            },
            "required" => ["task_instruction", "current_stage_summary", "next_stage_instruction"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "edit_task",
          "description" => "Edit an existing task",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "task_id" => %{
                "type" => "string",
                "description" => "The ID of the task to edit"
              },
              "task_instruction" => %{
                "type" => "string",
                "description" => "Updated task instruction"
              },
              "current_stage_summary" => %{
                "type" => "string",
                "description" => "Updated current stage summary"
              },
              "next_stage_instruction" => %{
                "type" => "string",
                "description" => "Updated next stage instruction"
              },
              "is_done" => %{
                "type" => "boolean",
                "description" => "Whether the task is completed"
              },
              "context" => %{
                "type" => "object",
                "description" => "Updated context data"
              }
            },
            "required" => ["task_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_task_stage",
          "description" => "Create a new stage for a task",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "task_id" => %{
                "type" => "string",
                "description" => "The ID of the task this stage belongs to"
              },
              "stage_name" => %{
                "type" => "string",
                "description" => "Name of the stage"
              },
              "stage_type" => %{
                "type" => "string",
                "description" => "Type of the stage (e.g., 'email', 'api_call', 'user_input')"
              },
              "tool_name" => %{
                "type" => "string",
                "description" => "Name of the tool to be used in this stage"
              },
              "tool_params" => %{
                "type" => "object",
                "description" => "Parameters for the tool"
              },
              "ai_reasoning" => %{
                "type" => "string",
                "description" => "AI's reasoning for this stage"
              },
              "status" => %{
                "type" => "string",
                "description" => "Status of the stage (e.g., 'pending', 'in_progress', 'completed', 'failed')"
              }
            },
            "required" => ["task_id", "stage_name", "stage_type", "tool_name", "ai_reasoning", "status"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "edit_task_stage",
          "description" => "Edit an existing task stage",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "stage_id" => %{
                "type" => "string",
                "description" => "The ID of the stage to edit"
              },
              "stage_name" => %{
                "type" => "string",
                "description" => "Updated stage name"
              },
              "stage_type" => %{
                "type" => "string",
                "description" => "Updated stage type"
              },
              "tool_name" => %{
                "type" => "string",
                "description" => "Updated tool name"
              },
              "tool_params" => %{
                "type" => "object",
                "description" => "Updated tool parameters"
              },
              "tool_result" => %{
                "type" => "object",
                "description" => "Result from tool execution"
              },
              "ai_reasoning" => %{
                "type" => "string",
                "description" => "Updated AI reasoning"
              },
              "status" => %{
                "type" => "string",
                "description" => "Updated status"
              },
              "started_at" => %{
                "type" => "string",
                "format" => "date-time",
                "description" => "When the stage started"
              },
              "completed_at" => %{
                "type" => "string",
                "format" => "date-time",
                "description" => "When the stage completed"
              },
              "error_message" => %{
                "type" => "string",
                "description" => "Error message if stage failed"
              }
            },
            "required" => ["stage_id"]
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

  # Private functions for tool implementations
  
   defp create_assistant_message(args, user_id) do
    session_id = Map.get(args, "session_id")
    message = Map.get(args, "message")

    case ChatMessages.create_assistant_message(session_id, user_id, message) do
      {:ok, chat_message} ->
        Logger.info("[ToolExecutor] Successfully created assistant message: #{chat_message.id}")
        {:ok, chat_message}
      {:error, changeset} ->
        Logger.error("[ToolExecutor] Failed to create assistant message: #{inspect(changeset.errors)}")
        {:error, "Failed to create assistant message: #{format_changeset_errors(changeset)}"}
    end
  end

  defp create_system_message(args, user_id) do
    session_id = Map.get(args, "session_id")
    message = Map.get(args, "message")

    case ChatMessages.create_system_message(session_id, user_id, message) do
      {:ok, chat_message} ->
        Logger.info("[ToolExecutor] Successfully created system message: #{chat_message.id}")
        {:ok, chat_message}
      {:error, changeset} ->
        Logger.error("[ToolExecutor] Failed to create system message: #{inspect(changeset.errors)}")
        {:error, "Failed to create system message: #{format_changeset_errors(changeset)}"}
    end
  end

  defp create_task(args, user_id) do
    task_attrs = args
    |> Map.put("user_id", user_id)
    |> Map.put("is_done", Map.get(args, "is_done", false))

    case Tasks.create_task(task_attrs) do
      {:ok, task} ->
        Logger.info("[ToolExecutor] Successfully created task: #{task.id}")
        {:ok, task}
      {:error, changeset} ->
        Logger.error("[ToolExecutor] Failed to create task: #{inspect(changeset.errors)}")
        {:error, "Failed to create task: #{format_changeset_errors(changeset)}"}
    end
  end

  defp edit_task(args, user_id) do
    task_id = Map.get(args, "task_id")

    case Tasks.get_task(task_id) do
      {:ok, task} ->
        # Verify user owns the task
        if task.user_id == user_id do
          update_attrs = Map.delete(args, "task_id")

          case Tasks.update_task(task, update_attrs) do
            {:ok, updated_task} ->
              Logger.info("[ToolExecutor] Successfully updated task: #{task_id}")
              {:ok, updated_task}
            {:error, changeset} ->
              Logger.error("[ToolExecutor] Failed to update task: #{inspect(changeset.errors)}")
              {:error, "Failed to update task: #{format_changeset_errors(changeset)}"}
          end
        else
          {:error, "Task not found or access denied"}
        end
      {:error, :not_found} ->
        {:error, "Task not found"}
    end
  end

  defp create_task_stage(args, user_id) do
    task_id = Map.get(args, "task_id")

    # Verify user owns the task
    case Tasks.get_task(task_id) do
      {:ok, task} when task.user_id == user_id ->
        stage_attrs = args
        |> Map.put("started_at", Map.get(args, "started_at", DateTime.utc_now()))
        |> Map.put("completed_at", Map.get(args, "completed_at", DateTime.utc_now()))
        |> Map.put("error_message", Map.get(args, "error_message", ""))

        case Tasks.create_task_stage(stage_attrs) do
          {:ok, stage} ->
            Logger.info("[ToolExecutor] Successfully created task stage: #{stage.id}")
            {:ok, stage}
          {:error, changeset} ->
            Logger.error("[ToolExecutor] Failed to create task stage: #{inspect(changeset.errors)}")
            {:error, "Failed to create task stage: #{format_changeset_errors(changeset)}"}
        end
      {:ok, _task} ->
        {:error, "Task not found or access denied"}
      {:error, :not_found} ->
        {:error, "Task not found"}
    end
  end

  defp edit_task_stage(args, user_id) do
    stage_id = Map.get(args, "stage_id")

    try do
      stage = Tasks.get_task_stage!(stage_id)

      # Get the associated task to verify user ownership
      case Tasks.get_task(stage.task_id) do
        {:ok, task} when task.user_id == user_id ->
          update_attrs = Map.delete(args, "stage_id")

          case Tasks.update_task_stage(stage, update_attrs) do
            {:ok, updated_stage} ->
              Logger.info("[ToolExecutor] Successfully updated task stage: #{stage_id}")
              {:ok, updated_stage}
            {:error, changeset} ->
              Logger.error("[ToolExecutor] Failed to update task stage: #{inspect(changeset.errors)}")
              {:error, "Failed to update task stage: #{format_changeset_errors(changeset)}"}
          end
        {:ok, _task} ->
          {:error, "Task stage not found or access denied"}
        {:error, :not_found} ->
          {:error, "Associated task not found"}
      end
    rescue
      Ecto.NoResultsError ->
        {:error, "Task stage not found"}
    end
  end

  defp format_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
