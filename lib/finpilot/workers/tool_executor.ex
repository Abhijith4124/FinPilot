defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools.
  """

  alias Finpilot.Accounts
  alias Finpilot.ChatMessages
  alias Finpilot.ChatSessions
  alias Finpilot.Gmail
  alias Finpilot.Services.Gmail, as: GmailService
  alias Finpilot.Services.Calendar, as: CalendarService
  alias Finpilot.Services.Hubspot, as: HubspotService

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

  def execute_tool("send_email", args, user_id) do
    to = Map.get(args, "to")
    subject = Map.get(args, "subject")
    body = Map.get(args, "body")
    cc = Map.get(args, "cc", [])
    bcc = Map.get(args, "bcc", [])

    if to == nil or subject == nil or body == nil do
      {:error, "to, subject, and body are required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.gmail_write do
            {:error, "Gmail write permission required"}
          else
            opts = []
            opts = if cc != [], do: Keyword.put(opts, :cc, cc), else: opts
            opts = if bcc != [], do: Keyword.put(opts, :bcc, bcc), else: opts

            case GmailService.send_email(user, to, subject, body, opts) do
              {:ok, response} ->
                {:ok, %{
                  "message_id" => response.id,
                  "thread_id" => response.threadId,
                  "status" => "sent"
                }}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("sync_emails", args, user_id) do
    max_results = Map.get(args, "max_results", 100)
    days_back = Map.get(args, "days_back", 30)
    async = Map.get(args, "async", true)

    case Accounts.get_user!(user_id) do
      user ->
        if not user.gmail_read do
          {:error, "Gmail read permission required"}
        else
          opts = [max_results: max_results, days_back: days_back]

          if async do
            case GmailService.sync_user_emails_async(user_id, opts) do
              {:ok, job} ->
                {:ok, %{
                  "job_id" => job.id,
                  "status" => "scheduled",
                  "message" => "Email sync job scheduled successfully"
                }}
              {:error, reason} ->
                {:error, reason}
            end
          else
            case GmailService.sync_user_emails(user_id, opts) do
              {:ok, result} ->
                {:ok, %{
                  "total_found" => result.total_found,
                  "successfully_synced" => result.successfully_synced,
                  "failed" => result.failed,
                  "status" => "completed"
                }}
              {:error, reason} ->
                {:error, reason}
            end
          end
        end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("reply_email", args, user_id) do
    original_email_id = Map.get(args, "original_email_id")
    reply_body = Map.get(args, "reply_body")
    include_original = Map.get(args, "include_original", true)

    if original_email_id == nil or reply_body == nil do
      {:error, "original_email_id and reply_body are required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.gmail_write do
            {:error, "Gmail write permission required"}
          else
            # Get the original email
            case Gmail.get_email!(original_email_id) do
              nil ->
                {:error, "Original email not found"}
              original_email ->
                if original_email.user_id != user_id do
                  {:error, "Access denied: email does not belong to user"}
                else
                  # Extract sender from original email to reply to
                  reply_to = original_email.sender
                  
                  # Create reply subject
                  reply_subject = if String.starts_with?(original_email.subject, "Re: ") do
                    original_email.subject
                  else
                    "Re: #{original_email.subject}"
                  end

                  # Build reply body
                  final_body = if include_original do
                    """
                    #{reply_body}

                    -----Original Message-----
                    From: #{original_email.sender}
                    Subject: #{original_email.subject}
                    Date: #{original_email.received_at}

                    #{original_email.content}
                    """
                  else
                    reply_body
                  end

                  case GmailService.send_email(user, reply_to, reply_subject, final_body) do
                    {:ok, response} ->
                      {:ok, %{
                        "message_id" => response.id,
                        "thread_id" => response.threadId,
                        "status" => "sent",
                        "reply_to" => reply_to,
                        "subject" => reply_subject
                      }}
                    {:error, reason} ->
                      {:error, reason}
                  end
                end
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("get_latest_emails", args, user_id) do
    limit = Map.get(args, "limit", 20)
    hours_back = Map.get(args, "hours_back", 24)

    case Accounts.get_user!(user_id) do
      user ->
        if not user.gmail_read do
          {:error, "Gmail read permission required"}
        else
          # Calculate the date range
          end_date = DateTime.utc_now()
          start_date = DateTime.add(end_date, -hours_back * 60 * 60, :second)

          opts = [
            limit: limit,
            from_date: start_date,
            to_date: end_date
          ]

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
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  # Calendar service functions
  def execute_tool("get_upcoming_events", args, user_id) do
    max_results = Map.get(args, "max_results", 10)
    days_ahead = Map.get(args, "days_ahead", 30)
    calendar_id = Map.get(args, "calendar_id", "primary")

    case Accounts.get_user!(user_id) do
      user ->
        if not user.calendar_read do
          {:error, "Calendar read permission required"}
        else
          opts = [max_results: max_results, days_ahead: days_ahead, calendar_id: calendar_id]
          
          case CalendarService.get_upcoming_events(user, opts) do
            {:ok, response} ->
              formatted_events = Enum.map(response.items || [], fn event ->
                %{
                  "id" => event.id,
                  "summary" => event.summary,
                  "description" => event.description,
                  "location" => event.location,
                  "start" => event.start,
                  "end" => event.end,
                  "attendees" => event.attendees,
                  "html_link" => event.htmlLink
                }
              end)
              {:ok, %{"events" => formatted_events, "count" => length(formatted_events)}}
            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("get_monthly_events", args, user_id) do
    year = Map.get(args, "year")
    month = Map.get(args, "month")
    max_results = Map.get(args, "max_results", 250)
    calendar_id = Map.get(args, "calendar_id", "primary")

    if year == nil or month == nil do
      {:error, "year and month are required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.calendar_read do
            {:error, "Calendar read permission required"}
          else
            opts = [max_results: max_results, calendar_id: calendar_id]
            
            case CalendarService.get_monthly_events(user, year, month, opts) do
              {:ok, response} ->
                formatted_events = Enum.map(response.items || [], fn event ->
                  %{
                    "id" => event.id,
                    "summary" => event.summary,
                    "description" => event.description,
                    "location" => event.location,
                    "start" => event.start,
                    "end" => event.end,
                    "attendees" => event.attendees,
                    "html_link" => event.htmlLink
                  }
                end)
                {:ok, %{"events" => formatted_events, "count" => length(formatted_events)}}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("create_calendar_event", args, user_id) do
    summary = Map.get(args, "summary")
    start_datetime = Map.get(args, "start_datetime")
    end_datetime = Map.get(args, "end_datetime")
    description = Map.get(args, "description")
    location = Map.get(args, "location")
    attendees = Map.get(args, "attendees", [])
    calendar_id = Map.get(args, "calendar_id", "primary")

    if summary == nil or start_datetime == nil or end_datetime == nil do
      {:error, "summary, start_datetime, and end_datetime are required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.calendar_write do
            {:error, "Calendar write permission required"}
          else
            # Parse datetime strings
            parsed_start = parse_datetime(start_datetime)
            parsed_end = parse_datetime(end_datetime)

            if parsed_start == nil or parsed_end == nil do
              {:error, "Invalid datetime format. Use ISO 8601 format."}
            else
              event_data = %{
                summary: summary,
                start_datetime: parsed_start,
                end_datetime: parsed_end,
                description: description,
                location: location,
                attendees: attendees
              }
              
              opts = [calendar_id: calendar_id]
              
              case CalendarService.create_event(user, event_data, opts) do
                {:ok, event} ->
                  {:ok, %{
                    "id" => event.id,
                    "summary" => event.summary,
                    "start" => event.start,
                    "end" => event.end,
                    "html_link" => event.htmlLink,
                    "status" => "created"
                  }}
                {:error, reason} ->
                  {:error, reason}
              end
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("update_calendar_event", args, user_id) do
    event_id = Map.get(args, "event_id")
    summary = Map.get(args, "summary")
    start_datetime = Map.get(args, "start_datetime")
    end_datetime = Map.get(args, "end_datetime")
    description = Map.get(args, "description")
    location = Map.get(args, "location")
    attendees = Map.get(args, "attendees")
    calendar_id = Map.get(args, "calendar_id", "primary")

    if event_id == nil do
      {:error, "event_id is required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.calendar_write do
            {:error, "Calendar write permission required"}
          else
            event_data = %{}
            event_data = if summary, do: Map.put(event_data, :summary, summary), else: event_data
            event_data = if description, do: Map.put(event_data, :description, description), else: event_data
            event_data = if location, do: Map.put(event_data, :location, location), else: event_data
            event_data = if attendees, do: Map.put(event_data, :attendees, attendees), else: event_data
            
            # Parse datetime strings if provided
            event_data = if start_datetime do
              parsed_start = parse_datetime(start_datetime)
              if parsed_start, do: Map.put(event_data, :start_datetime, parsed_start), else: event_data
            else
              event_data
            end
            
            event_data = if end_datetime do
              parsed_end = parse_datetime(end_datetime)
              if parsed_end, do: Map.put(event_data, :end_datetime, parsed_end), else: event_data
            else
              event_data
            end
            
            opts = [calendar_id: calendar_id]
            
            case CalendarService.update_event(user, event_id, event_data, opts) do
              {:ok, event} ->
                {:ok, %{
                  "id" => event.id,
                  "summary" => event.summary,
                  "start" => event.start,
                  "end" => event.end,
                  "html_link" => event.htmlLink,
                  "status" => "updated"
                }}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("delete_calendar_event", args, user_id) do
    event_id = Map.get(args, "event_id")
    calendar_id = Map.get(args, "calendar_id", "primary")

    if event_id == nil do
      {:error, "event_id is required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.calendar_write do
            {:error, "Calendar write permission required"}
          else
            opts = [calendar_id: calendar_id]
            
            case CalendarService.delete_event(user, event_id, opts) do
              {:ok, :deleted} ->
                {:ok, %{"status" => "deleted", "event_id" => event_id}}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("search_calendar_events", args, user_id) do
    query = Map.get(args, "query")
    max_results = Map.get(args, "max_results", 50)
    calendar_id = Map.get(args, "calendar_id", "primary")

    if query == nil or String.trim(query) == "" do
      {:error, "query is required and cannot be empty"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.calendar_read do
            {:error, "Calendar read permission required"}
          else
            opts = [max_results: max_results, calendar_id: calendar_id]
            
            case CalendarService.search_events(user, query, opts) do
              {:ok, response} ->
                formatted_events = Enum.map(response.items || [], fn event ->
                  %{
                    "id" => event.id,
                    "summary" => event.summary,
                    "description" => event.description,
                    "location" => event.location,
                    "start" => event.start,
                    "end" => event.end,
                    "attendees" => event.attendees,
                    "html_link" => event.htmlLink
                  }
                end)
                {:ok, %{"events" => formatted_events, "count" => length(formatted_events)}}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  # HubSpot service functions
  def execute_tool("get_hubspot_contacts", args, user_id) do
    limit = Map.get(args, "limit", 100)

    case Accounts.get_user!(user_id) do
      user ->
        if not user.hubspot do
          {:error, "HubSpot integration required"}
        else
          opts = [limit: limit]
          
          case HubspotService.get_contacts(user, opts) do
            {:ok, response} ->
              formatted_contacts = Enum.map(response["results"] || [], fn contact ->
                properties = contact["properties"] || %{}
                %{
                  "id" => contact["id"],
                  "email" => properties["email"],
                  "firstname" => properties["firstname"],
                  "lastname" => properties["lastname"],
                  "company" => properties["company"],
                  "phone" => properties["phone"],
                  "created_at" => contact["createdAt"],
                  "updated_at" => contact["updatedAt"]
                }
              end)
              {:ok, %{"contacts" => formatted_contacts, "count" => length(formatted_contacts)}}
            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("create_hubspot_contact", args, user_id) do
    email = Map.get(args, "email")
    firstname = Map.get(args, "firstname")
    lastname = Map.get(args, "lastname")
    company = Map.get(args, "company")
    phone = Map.get(args, "phone")

    if email == nil do
      {:error, "email is required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.hubspot do
            {:error, "HubSpot integration required"}
          else
            contact_data = %{"email" => email}
            contact_data = if firstname, do: Map.put(contact_data, "firstname", firstname), else: contact_data
            contact_data = if lastname, do: Map.put(contact_data, "lastname", lastname), else: contact_data
            contact_data = if company, do: Map.put(contact_data, "company", company), else: contact_data
            contact_data = if phone, do: Map.put(contact_data, "phone", phone), else: contact_data
            
            case HubspotService.create_contact(user, contact_data) do
              {:ok, contact} ->
                properties = contact["properties"] || %{}
                {:ok, %{
                  "id" => contact["id"],
                  "email" => properties["email"],
                  "firstname" => properties["firstname"],
                  "lastname" => properties["lastname"],
                  "company" => properties["company"],
                  "phone" => properties["phone"],
                  "status" => "created"
                }}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("update_hubspot_contact", args, user_id) do
    contact_id = Map.get(args, "contact_id")
    email = Map.get(args, "email")
    firstname = Map.get(args, "firstname")
    lastname = Map.get(args, "lastname")
    company = Map.get(args, "company")
    phone = Map.get(args, "phone")

    if contact_id == nil do
      {:error, "contact_id is required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.hubspot do
            {:error, "HubSpot integration required"}
          else
            contact_data = %{}
            contact_data = if email, do: Map.put(contact_data, "email", email), else: contact_data
            contact_data = if firstname, do: Map.put(contact_data, "firstname", firstname), else: contact_data
            contact_data = if lastname, do: Map.put(contact_data, "lastname", lastname), else: contact_data
            contact_data = if company, do: Map.put(contact_data, "company", company), else: contact_data
            contact_data = if phone, do: Map.put(contact_data, "phone", phone), else: contact_data
            
            if map_size(contact_data) == 0 do
              {:error, "At least one field to update is required"}
            else
              case HubspotService.update_contact(user, contact_id, contact_data) do
                {:ok, contact} ->
                  properties = contact["properties"] || %{}
                  {:ok, %{
                    "id" => contact["id"],
                    "email" => properties["email"],
                    "firstname" => properties["firstname"],
                    "lastname" => properties["lastname"],
                    "company" => properties["company"],
                    "phone" => properties["phone"],
                    "status" => "updated"
                  }}
                {:error, reason} ->
                  {:error, reason}
              end
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("search_hubspot_contacts", args, user_id) do
    search_query = Map.get(args, "search_query")
    limit = Map.get(args, "limit", 100)

    if search_query == nil or String.trim(search_query) == "" do
      {:error, "search_query is required and cannot be empty"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.hubspot do
            {:error, "HubSpot integration required"}
          else
            opts = [limit: limit]
            
            case HubspotService.search_contacts(user, search_query, opts) do
              {:ok, response} ->
                formatted_contacts = Enum.map(response["results"] || [], fn contact ->
                  properties = contact["properties"] || %{}
                  %{
                    "id" => contact["id"],
                    "email" => properties["email"],
                    "firstname" => properties["firstname"],
                    "lastname" => properties["lastname"],
                    "company" => properties["company"],
                    "phone" => properties["phone"],
                    "created_at" => contact["createdAt"],
                    "updated_at" => contact["updatedAt"]
                  }
                end)
                {:ok, %{"contacts" => formatted_contacts, "count" => length(formatted_contacts)}}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
  end

  def execute_tool("get_hubspot_contact", args, user_id) do
    contact_id = Map.get(args, "contact_id")

    if contact_id == nil do
      {:error, "contact_id is required"}
    else
      case Accounts.get_user!(user_id) do
        user ->
          if not user.hubspot do
            {:error, "HubSpot integration required"}
          else
            case HubspotService.get_contact(user, contact_id) do
              {:ok, contact} ->
                properties = contact["properties"] || %{}
                {:ok, %{
                  "id" => contact["id"],
                  "email" => properties["email"],
                  "firstname" => properties["firstname"],
                  "lastname" => properties["lastname"],
                  "company" => properties["company"],
                  "phone" => properties["phone"],
                  "created_at" => contact["createdAt"],
                  "updated_at" => contact["updatedAt"]
                }}
              {:error, reason} ->
                {:error, reason}
            end
          end
      end
    end
  rescue
    Ecto.NoResultsError -> {:error, "User not found"}
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

  defp parse_datetime(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} ->
        case Date.from_iso8601(datetime_string) do
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
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "send_email",
          "description" => "Send an email using Gmail API",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "to" => %{"type" => "string", "description" => "Recipient email address"},
              "subject" => %{"type" => "string", "description" => "Email subject"},
              "body" => %{"type" => "string", "description" => "Email body content (HTML or plain text)"},
              "cc" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "CC recipients (optional)"},
              "bcc" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "BCC recipients (optional)"}
            },
            "required" => ["to", "subject", "body"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "sync_emails",
          "description" => "Sync user's latest emails from Gmail",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "max_results" => %{"type" => "integer", "description" => "Maximum number of emails to sync (default: 100)", "minimum" => 1, "maximum" => 500},
              "days_back" => %{"type" => "integer", "description" => "Number of days back to sync (default: 30)", "minimum" => 1, "maximum" => 365},
              "async" => %{"type" => "boolean", "description" => "Whether to run sync asynchronously (default: true)"}
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "reply_email",
          "description" => "Reply to an existing email",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "original_email_id" => %{"type" => "string", "description" => "ID of the original email to reply to"},
              "reply_body" => %{"type" => "string", "description" => "Reply message content"},
              "include_original" => %{"type" => "boolean", "description" => "Whether to include original message in reply (default: true)"}
            },
            "required" => ["original_email_id", "reply_body"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_latest_emails",
          "description" => "Get the most recent emails from the user's Gmail",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "limit" => %{"type" => "integer", "description" => "Maximum number of emails to retrieve (default: 20)", "minimum" => 1, "maximum" => 100},
              "hours_back" => %{"type" => "integer", "description" => "Number of hours back to look for emails (default: 24)", "minimum" => 1, "maximum" => 168}
            },
            "required" => []
          }
        }
      },
      # Calendar tools
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_upcoming_events",
          "description" => "Get upcoming calendar events for the user",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "max_results" => %{"type" => "integer", "description" => "Maximum number of events to retrieve (default: 10)", "minimum" => 1, "maximum" => 100},
              "days_ahead" => %{"type" => "integer", "description" => "Number of days ahead to look for events (default: 30)", "minimum" => 1, "maximum" => 365},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID to query (default: primary)"}
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_monthly_events",
          "description" => "Get calendar events for a specific month",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "year" => %{"type" => "integer", "description" => "Year (e.g., 2024)"},
              "month" => %{"type" => "integer", "description" => "Month (1-12)", "minimum" => 1, "maximum" => 12},
              "max_results" => %{"type" => "integer", "description" => "Maximum number of events to retrieve (default: 250)", "minimum" => 1, "maximum" => 500},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID to query (default: primary)"}
            },
            "required" => ["year", "month"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_calendar_event",
          "description" => "Create a new calendar event",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "summary" => %{"type" => "string", "description" => "Event title/summary"},
              "start_datetime" => %{"type" => "string", "description" => "Start datetime (ISO 8601 format)"},
              "end_datetime" => %{"type" => "string", "description" => "End datetime (ISO 8601 format)"},
              "description" => %{"type" => "string", "description" => "Event description (optional)"},
              "location" => %{"type" => "string", "description" => "Event location (optional)"},
              "attendees" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "List of attendee emails (optional)"},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID to create event in (default: primary)"}
            },
            "required" => ["summary", "start_datetime", "end_datetime"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "update_calendar_event",
          "description" => "Update an existing calendar event",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "event_id" => %{"type" => "string", "description" => "ID of the event to update"},
              "summary" => %{"type" => "string", "description" => "Event title/summary (optional)"},
              "start_datetime" => %{"type" => "string", "description" => "Start datetime (ISO 8601 format, optional)"},
              "end_datetime" => %{"type" => "string", "description" => "End datetime (ISO 8601 format, optional)"},
              "description" => %{"type" => "string", "description" => "Event description (optional)"},
              "location" => %{"type" => "string", "description" => "Event location (optional)"},
              "attendees" => %{"type" => "array", "items" => %{"type" => "string"}, "description" => "List of attendee emails (optional)"},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID (default: primary)"}
            },
            "required" => ["event_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "delete_calendar_event",
          "description" => "Delete a calendar event",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "event_id" => %{"type" => "string", "description" => "ID of the event to delete"},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID (default: primary)"}
            },
            "required" => ["event_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_calendar_events",
          "description" => "Search for calendar events matching a query",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "query" => %{"type" => "string", "description" => "Search query text"},
              "max_results" => %{"type" => "integer", "description" => "Maximum number of results (default: 50)", "minimum" => 1, "maximum" => 100},
              "calendar_id" => %{"type" => "string", "description" => "Calendar ID to search (default: primary)"}
            },
            "required" => ["query"]
          }
        }
      },
      # HubSpot tools
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_hubspot_contacts",
          "description" => "Get all contacts from HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "limit" => %{"type" => "integer", "description" => "Maximum number of contacts to retrieve (default: 100)", "minimum" => 1, "maximum" => 500}
            },
            "required" => []
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_hubspot_contact",
          "description" => "Create a new contact in HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "email" => %{"type" => "string", "description" => "Contact email address"},
              "firstname" => %{"type" => "string", "description" => "Contact first name (optional)"},
              "lastname" => %{"type" => "string", "description" => "Contact last name (optional)"},
              "company" => %{"type" => "string", "description" => "Contact company (optional)"},
              "phone" => %{"type" => "string", "description" => "Contact phone number (optional)"}
            },
            "required" => ["email"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "update_hubspot_contact",
          "description" => "Update an existing contact in HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "contact_id" => %{"type" => "string", "description" => "ID of the contact to update"},
              "email" => %{"type" => "string", "description" => "Contact email address (optional)"},
              "firstname" => %{"type" => "string", "description" => "Contact first name (optional)"},
              "lastname" => %{"type" => "string", "description" => "Contact last name (optional)"},
              "company" => %{"type" => "string", "description" => "Contact company (optional)"},
              "phone" => %{"type" => "string", "description" => "Contact phone number (optional)"}
            },
            "required" => ["contact_id"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_hubspot_contacts",
          "description" => "Search for contacts in HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "search_query" => %{"type" => "string", "description" => "Search query (typically email or name)"},
              "limit" => %{"type" => "integer", "description" => "Maximum number of results (default: 100)", "minimum" => 1, "maximum" => 500}
            },
            "required" => ["search_query"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_hubspot_contact",
          "description" => "Get a specific contact by ID from HubSpot CRM",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "contact_id" => %{"type" => "string", "description" => "ID of the contact to retrieve"}
            },
            "required" => ["contact_id"]
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

    5. send_email
       - Description: Send an email using Gmail API
       - Required: to (string), subject (string), body (string)
       - Optional: cc (array of strings), bcc (array of strings)
       - Returns: Map with message_id, thread_id, and status

    6. sync_emails
       - Description: Sync user's latest emails from Gmail
       - Required: None
       - Optional: max_results (integer, 1-500, default: 100), days_back (integer, 1-365, default: 30), async (boolean, default: true)
       - Returns: Sync status and statistics

    7. reply_email
       - Description: Reply to an existing email
       - Required: original_email_id (string), reply_body (string)
       - Optional: include_original (boolean, default: true)
       - Returns: Map with message_id, thread_id, status, reply_to, and subject

    8. get_latest_emails
       - Description: Get the most recent emails from the user's Gmail
       - Required: None
       - Optional: limit (integer, 1-100, default: 20), hours_back (integer, 1-168, default: 24)
       - Returns: List of recent emails with full email details
    """
  end
end
