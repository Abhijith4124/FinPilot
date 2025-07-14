defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools.
  """

  alias Finpilot.Accounts
  alias Finpilot.ChatMessages
  alias Finpilot.ChatSessions
  alias Finpilot.Gmail

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

def execute_tool("get_emails", args, user_id) do
    limit = Map.get(args, "limit", 50)
    offset = Map.get(args, "offset", 0)
    sender = Map.get(args, "sender")
    subject_contains = Map.get(args, "subject_contains")
    content_contains = Map.get(args, "content_contains")
    from_date = Map.get(args, "from_date")
    to_date = Map.get(args, "to_date")
    labels = Map.get(args, "labels")

    # Parse dates if provided
    parsed_from_date = if from_date, do: parse_date(from_date), else: nil
    parsed_to_date = if to_date, do: parse_date(to_date), else: nil

    opts = [
      limit: limit,
      offset: offset,
      sender: sender,
      subject_contains: subject_contains,
      content_contains: content_contains,
      from_date: parsed_from_date,
      to_date: parsed_to_date,
      labels: labels
    ]
    |> Enum.filter(fn {_k, v} -> v != nil end)

    emails = Gmail.list_user_emails(user_id, opts)
    formatted = Enum.map(emails, fn email ->
      %{
        "id" => email.id,
        "gmail_message_id" => email.gmail_message_id,
        "subject" => email.subject,
        "sender" => email.sender,
        "recipients" => email.recipients,
        "content" => email.content,
        "received_at" => email.received_at,
        "thread_id" => email.thread_id,
        "labels" => email.labels,
        "processed_at" => email.processed_at,
        "attachments" => email.attachments
      }
    end)
    
    {:ok, %{"emails" => formatted, "count" => length(formatted)}}
  end

  def execute_tool("search_emails", args, user_id) do
    query_text = Map.get(args, "query")
    limit = Map.get(args, "limit", 10)
    threshold = Map.get(args, "threshold", 0.8)

    if query_text == nil or String.trim(query_text) == "" do
      {:error, "query is required and cannot be empty"}
    else
      opts = [limit: limit, threshold: threshold]
      
      case Gmail.search_emails_by_content(user_id, query_text, opts) do
        {:error, reason} -> {:error, reason}
        results ->
          formatted = Enum.map(results, fn %{email: email, similarity: similarity} ->
            %{
              "email" => %{
                "id" => email.id,
                "gmail_message_id" => email.gmail_message_id,
                "subject" => email.subject,
                "sender" => email.sender,
                "recipients" => email.recipients,
                "content" => email.content,
                "received_at" => email.received_at,
                "thread_id" => email.thread_id,
                "labels" => email.labels,
                "processed_at" => email.processed_at,
                "attachments" => email.attachments
              },
              "similarity" => similarity
            }
          end)
          
          {:ok, %{"results" => formatted, "count" => length(formatted)}}
      end
    end
  end

  def execute_tool(tool_name, _args, _user_id) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  defp parse_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} ->
        case Date.from_iso8601(date_string) do
          {:ok, date} -> DateTime.new!(date, ~T[00:00:00])
          {:error, _} -> nil
        end
    end
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
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_emails",
          "description" => "Retrieve emails from the user's Gmail with pagination and filtering options",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "limit" => %{"type" => "integer", "description" => "Maximum number of emails to retrieve (default: 50)", "minimum" => 1, "maximum" => 100},
              "offset" => %{"type" => "integer", "description" => "Number of emails to skip for pagination (default: 0)", "minimum" => 0},
              "sender" => %{"type" => "string", "description" => "Filter by sender email address"},
              "subject_contains" => %{"type" => "string", "description" => "Filter by text contained in subject"},
              "content_contains" => %{"type" => "string", "description" => "Filter by text contained in email content"},
              "from_date" => %{"type" => "string", "description" => "Filter emails from this date (ISO 8601 format)"},
              "to_date" => %{"type" => "string", "description" => "Filter emails up to this date (ISO 8601 format)"},
              "labels" => %{"type" => "string", "description" => "Filter by Gmail labels"}
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_emails",
          "description" => "Search emails using AI-powered semantic search based on content similarity",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "The search query text to find similar emails"},
              "limit" => %{"type" => "integer", "description" => "Maximum number of results to return (default: 10)", "minimum" => 1, "maximum" => 50},
              "threshold" => %{"type" => "number", "description" => "Similarity threshold (0.0 to 1.0, default: 0.8)", "minimum" => 0.0, "maximum" => 1.0}
            },
            "required" => ["query"]
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
       - Description: Retrieve non-sensitive information for the specified user (must be current user), you can check if the user has access to certain permission using this tool
       - Required: user_id (string)
       - Returns: Map with id, name, username, email, picture, verified, gmail_read, gmail_write, calendar_read, calendar_write, hubspot

    3. get_emails
       - Description: Retrieve emails from the user's Gmail with pagination and filtering options
       - Required: None
       - Optional: limit (integer, 1-100, default: 50), offset (integer, default: 0), sender (string), subject_contains (string), content_contains (string), from_date (ISO 8601), to_date (ISO 8601), labels (string)
       - Returns: List of emails with id, gmail_message_id, subject, sender, recipients, content, received_at, thread_id, labels, processed_at, attachments

    4. search_emails
       - Description: Search emails using AI-powered semantic search based on content similarity
       - Required: query (string)
       - Optional: limit (integer, 1-50, default: 10), threshold (number, 0.0-1.0, default: 0.8)
       - Returns: List of results with email object and similarity score
    """
  end
end
