defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools.
  """

  alias Finpilot.Accounts
  alias Finpilot.ChatMessages
  alias Finpilot.ChatSessions

  def execute_tool("get_chat_messages", args, user_id) do
    session_id = Map.get(args, "session_id")
    limit = Map.get(args, "limit", 50)
    offset = Map.get(args, "offset", 0)

    if session_id == nil do
      {:error, "session_id is required"}
    else
      with {:ok, session} <- ChatSessions.get_chat_session(session_id),
           true <- session.user_id == user_id do
        messages = ChatMessages.list_messages_by_session(session_id, limit: limit, offset: offset)
        formatted = Enum.map(messages, fn msg ->
          %{
            "id" => msg.id,
            "role" => msg.role,
            "message" => msg.message,
            "inserted_at" => msg.inserted_at,
            "session_id" => msg.session_id,
            "user_id" => msg.user_id
          }
        end)
        {:ok, %{"messages" => formatted, "count" => length(formatted)}}
      else
        false -> {:error, "Access denied: session does not belong to user"}
        {:error, :not_found} -> {:error, "Session not found"}
      end
    end
  end

  def execute_tool("get_user_info", args, current_user_id) do
    requested_user_id = Map.get(args, "user_id")

    if requested_user_id != current_user_id do
      {:error, "Access denied: cannot access other users' information"}
    else
      case Accounts.get_user!(requested_user_id) do
        user ->
          safe_user = %{
            "id" => user.id,
            "name" => user.name,
            "username" => user.username,
            "email" => user.email,
            "picture" => user.picture,
            "verified" => user.verified,
            "gmail_read" => user.gmail_read,
            "gmail_write" => user.gmail_write,
            "calendar_read" => user.calendar_read,
            "calendar_write" => user.calendar_write,
            "hubspot" => user.hubspot
          }
          {:ok, safe_user}
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

def execute_tool(tool_name, _args, _user_id) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  def get_tool_definitions do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_chat_messages",
          "description" => "Retrieve chat messages from a specific chat session with pagination support",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "session_id" => %{"type" => "string", "description" => "The ID of the chat session"},
              "limit" => %{"type" => "integer", "description" => "Maximum number of messages to retrieve (default: 50)", "minimum" => 1, "maximum" => 100},
              "offset" => %{"type" => "integer", "description" => "Number of messages to skip for pagination (default: 0)", "minimum" => 0}
            },
            "required" => ["session_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_user_info",
          "description" => "Retrieve non-sensitive information for the specified user (must be current user)",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "user_id" => %{"type" => "string", "description" => "The ID of the user (must match current user)"}
            },
            "required" => ["user_id"]
          }
        }
      }
    ]
  end

  def format_tool_definitions_for_prompt do
    """
    Available Tools:

    1. get_chat_messages
       - Description: Retrieve chat messages from a specific chat session
       - Required: session_id (string)
       - Optional: limit (integer, 1-100, default: 50), offset (integer, default: 0)
       - Returns: List of messages with id, role, message, inserted_at, session_id, user_id

    2. get_user_info
       - Description: Retrieve non-sensitive information for the specified user (must be current user), you can check if the user has acess to certain permission using this tool
       - Required: user_id (string)
       - Returns: Map with id, name, username, email, picture, verified, gmail_read, gmail_write, calendar_read, calendar_write, hubspot
    """
  end
end
