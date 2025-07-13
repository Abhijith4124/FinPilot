defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools for memory and search operations.
  This module provides a centralized way to execute various tools
  that the AI can call to search and retrieve relevant context.
  """

  require Logger
  alias Finpilot.Services.Memory

  @doc """
  Execute a tool with the given name, arguments, and user context.
  
  ## Examples
  
      iex> ToolExecutor.execute_tool("search_tasks", %{"query" => "Send email"}, user_id)
      {:ok, [%{id: 1, task_instruction: "...", similarity: 0.85}]}
      
      iex> ToolExecutor.execute_tool("search_chat_messages", %{"query" => "Hello"}, user_id)
      {:ok, [%{id: 1, message: "...", similarity: 0.90}]}
      
      iex> ToolExecutor.execute_tool("find_relevant_context", %{"query" => "email setup"}, user_id)
      {:ok, %{tasks: [...], messages: [...]}}
  """
  def execute_tool(tool_name, args, user_id) do
    case tool_name do
      "search_tasks" -> search_tasks(args, user_id)
      "search_chat_messages" -> search_chat_messages(args, user_id)
      "find_relevant_context" -> find_relevant_context(args, user_id)

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
          "name" => "search_tasks",
          "description" => "Search for similar tasks based on semantic similarity",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{
                "type" => "string",
                "description" => "The search query to find similar tasks"
              },
              "limit" => %{
                "type" => "integer",
                "description" => "Maximum number of results to return (default: 10)"
              },
              "threshold" => %{
                "type" => "number",
                "description" => "Similarity threshold (default: 0.7)"
              },
              "include_completed" => %{
                "type" => "boolean",
                "description" => "Include completed tasks (default: true)"
              }
            },
            "required" => ["query"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_chat_messages",
          "description" => "Search for similar chat messages based on semantic similarity",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{
                "type" => "string",
                "description" => "The search query to find similar messages"
              },
              "limit" => %{
                "type" => "integer",
                "description" => "Maximum number of results to return (default: 10)"
              },
              "threshold" => %{
                "type" => "number",
                "description" => "Similarity threshold (default: 0.7)"
              },
              "role_filter" => %{
                "type" => "string",
                "description" => "Filter by message role (user, assistant, system)"
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Filter by specific chat session"
              }
            },
            "required" => ["query"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "find_relevant_context",
          "description" => "Find relevant context by searching both tasks and chat messages",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{
                "type" => "string",
                "description" => "The search query to find relevant context"
              },
              "task_limit" => %{
                "type" => "integer",
                "description" => "Maximum number of task results (default: 5)"
              },
              "message_limit" => %{
                "type" => "integer",
                "description" => "Maximum number of message results (default: 5)"
              },
              "threshold" => %{
                "type" => "number",
                "description" => "Similarity threshold (default: 0.7)"
              }
            },
            "required" => ["query"]
          }
        }
      }
    ]
  end

  # Private functions for tool implementations
  
  defp search_tasks(args, user_id) do
    query = Map.get(args, "query")
    opts = build_search_opts(args, [:limit, :threshold, :include_completed])

    case Memory.search_tasks(user_id, query, opts) do
      {:ok, tasks} ->
        Logger.info("[ToolExecutor] Successfully searched tasks: #{length(tasks)} results")
        {:ok, tasks}
      {:error, reason} ->
        Logger.error("[ToolExecutor] Failed to search tasks: #{reason}")
        {:error, "Failed to search tasks: #{reason}"}
    end
  end

  defp search_chat_messages(args, user_id) do
    query = Map.get(args, "query")
    opts = build_search_opts(args, [:limit, :threshold, :role_filter, :session_id])

    case Memory.search_chat_messages(user_id, query, opts) do
      {:ok, messages} ->
        Logger.info("[ToolExecutor] Successfully searched chat messages: #{length(messages)} results")
        {:ok, messages}
      {:error, reason} ->
        Logger.error("[ToolExecutor] Failed to search chat messages: #{reason}")
        {:error, "Failed to search chat messages: #{reason}"}
    end
  end

  defp find_relevant_context(args, user_id) do
    query = Map.get(args, "query")
    opts = build_search_opts(args, [:task_limit, :message_limit, :threshold])

    case Memory.find_relevant_context(user_id, query, opts) do
      {:ok, context} ->
        Logger.info("[ToolExecutor] Successfully found relevant context: #{length(context.tasks)} tasks, #{length(context.messages)} messages")
        {:ok, context}
      {:error, reason} ->
        Logger.error("[ToolExecutor] Failed to find relevant context: #{reason}")
        {:error, "Failed to find relevant context: #{reason}"}
    end
  end

  defp build_search_opts(args, allowed_keys) do
    allowed_keys
    |> Enum.reduce([], fn key, acc ->
      case Map.get(args, Atom.to_string(key)) do
        nil -> acc
        value -> [{key, value} | acc]
      end
    end)
  end
end
