defmodule Finpilot.Services.Gmail do
  @moduledoc """
  Gmail API service for managing emails, sending messages, and retrieving email data.
  """

  alias Finpilot.Accounts.User
  alias Finpilot.Gmail
  alias Finpilot.Gmail.{Email, SyncStatus}
  alias Finpilot.Repo
  alias GoogleApi.Gmail.V1.Api.Users
  alias GoogleApi.Gmail.V1.Connection
  alias GoogleApi.Gmail.V1.Model.{Message, Draft}
  alias OAuth2
  require Logger

  @doc """
  Sends an email using Gmail API.
  
  ## Parameters
  - user: User struct with valid Gmail tokens
  - to: Recipient email address
  - subject: Email subject
  - body: Email body (HTML or plain text)
  - opts: Optional parameters like cc, bcc, attachments
  """
  def send_email(%User{} = user, to, subject, body, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      cc = Keyword.get(opts, :cc, [])
      bcc = Keyword.get(opts, :bcc, [])
      from = Keyword.get(opts, :from, user.email)
      
      # Build email message
      email_content = build_email_message(from, to, cc, bcc, subject, body)
      
      # Create message object
      message = %Message{
        raw: Base.url_encode64(email_content, padding: false)
      }
      
      case Users.gmail_users_messages_send(conn, "me", body: message) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to send email: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets a specific email by message ID.
  """
  def get_email(%User{} = user, message_id, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      format = Keyword.get(opts, :format, "full")
      
      case Users.gmail_users_messages_get(conn, "me", message_id, format: format) do
        {:ok, message} ->
          {:ok, message}
        {:error, error} ->
          {:error, "Failed to get email: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets emails from a specific date range.
  
  ## Parameters
  - user: User struct
  - start_date: Start date (DateTime or date string)
  - end_date: End date (DateTime or date string)
  - opts: Additional options like max_results, label_ids
  """
  def get_emails_by_date_range(%User{} = user, start_date, end_date, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      max_results = Keyword.get(opts, :max_results, 100)
      label_ids = Keyword.get(opts, :label_ids, [])
      
      # Format dates for Gmail query
      start_query = format_date_for_query(start_date)
      end_query = format_date_for_query(end_date)
      
      query = "after:#{start_query} before:#{end_query}"
      
      list_opts = [
        q: query,
        maxResults: max_results
      ]
      
      list_opts = if length(label_ids) > 0 do
        Keyword.put(list_opts, :labelIds, label_ids)
      else
        list_opts
      end
      
      case Users.gmail_users_messages_list(conn, "me", list_opts) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to get emails by date range: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets messages after a specific history ID to retrieve new emails.
  This is useful for incremental syncing.
  """
  def get_messages_after_history_id(%User{} = user, history_id, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      max_results = Keyword.get(opts, :max_results, 100)
      label_ids = Keyword.get(opts, :label_ids, [])
      
      history_opts = [
        startHistoryId: history_id,
        maxResults: max_results
      ]
      
      history_opts = if length(label_ids) > 0 do
        Keyword.put(history_opts, :labelId, label_ids)
      else
        history_opts
      end
      
      case Users.gmail_users_history_list(conn, "me", history_opts) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to get messages after history ID: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Lists messages with optional query parameters.
  """
  def list_messages(%User{} = user, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      query = Keyword.get(opts, :query, "")
      max_results = Keyword.get(opts, :max_results, 100)
      label_ids = Keyword.get(opts, :label_ids, [])
      page_token = Keyword.get(opts, :page_token)
      
      list_opts = [
        maxResults: max_results
      ]
      
      list_opts = if query != "" do
        Keyword.put(list_opts, :q, query)
      else
        list_opts
      end
      
      list_opts = if length(label_ids) > 0 do
        Keyword.put(list_opts, :labelIds, label_ids)
      else
        list_opts
      end
      
      list_opts = if page_token do
        Keyword.put(list_opts, :pageToken, page_token)
      else
        list_opts
      end
      
      case Users.gmail_users_messages_list(conn, "me", list_opts) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to list messages: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets user's Gmail profile information.
  """
  def get_profile(%User{} = user) do
    with {:ok, conn} <- get_connection(user) do
      case Users.gmail_users_get_profile(conn, "me") do
        {:ok, profile} ->
          {:ok, profile}
        {:error, error} ->
          {:error, "Failed to get profile: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets all labels for the user.
  """
  def list_labels(%User{} = user) do
    with {:ok, conn} <- get_connection(user) do
      case Users.gmail_users_labels_list(conn, "me") do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to list labels: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Creates a draft email.
  """
  def create_draft(%User{} = user, to, subject, body, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      cc = Keyword.get(opts, :cc, [])
      bcc = Keyword.get(opts, :bcc, [])
      from = Keyword.get(opts, :from, user.email)
      
      # Build email message
      email_content = build_email_message(from, to, cc, bcc, subject, body)
      
      # Create draft object
      draft = %Draft{
        message: %Message{
          raw: Base.url_encode64(email_content, padding: false)
        }
      }
      
      case Users.gmail_users_drafts_create(conn, "me", body: draft) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to create draft: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Searches for emails using Gmail search syntax.
  """
  def search_emails(%User{} = user, query, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      max_results = Keyword.get(opts, :max_results, 100)
      
      case Users.gmail_users_messages_list(conn, "me", q: query, maxResults: max_results) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to search emails: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets the current history ID for the user's mailbox.
  This is useful for setting up incremental sync.
  """
  def get_current_history_id(%User{} = user) do
    with {:ok, conn} <- get_connection(user) do
      case Users.gmail_users_get_profile(conn, "me") do
        {:ok, %{historyId: history_id}} ->
          {:ok, history_id}
        {:error, error} ->
          {:error, "Failed to get current history ID: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Modifies labels on a message (add/remove labels).
  """
  def modify_message_labels(%User{} = user, message_id, add_label_ids \\ [], remove_label_ids \\ []) do
    with {:ok, conn} <- get_connection(user) do
      modify_request = %{
        addLabelIds: add_label_ids,
        removeLabelIds: remove_label_ids
      }
      
      case Users.gmail_users_messages_modify(conn, "me", message_id, body: modify_request) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to modify message labels: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Syncs user emails from Gmail and saves them to the database.
  
  ## Parameters
  - user_id: The user ID to sync emails for
  - opts: Optional parameters like max_results, days_back
  
  ## Returns
  - {:ok, sync_result} - Success with sync statistics
  - {:error, reason} - Error during sync
  """
  def sync_user_emails(user_id, opts \\ []) do
    Logger.info("Starting email sync for user #{user_id}")
    
    try do
      case Finpilot.Accounts.get_user!(user_id) do
        %User{} = user ->
          do_sync_user_emails(user, opts)
        nil ->
          {:error, "User not found"}
      end
    rescue
      Ecto.NoResultsError ->
        {:error, "User not found"}
    end
  end

  defp do_sync_user_emails(%User{} = user, opts) do
    max_results = Keyword.get(opts, :max_results, 100)
    days_back = Keyword.get(opts, :days_back, 30)
    
    # Get or create sync status
    sync_status = Gmail.get_sync_status_by_user_id(user.id) || create_initial_sync_status(user.id)
    
    # Update sync status to "syncing"
    {:ok, _} = Gmail.update_sync_status(sync_status, %{
      sync_status: "syncing",
      last_error_message: nil
    })
    
    try do
      # Calculate date range
      end_date = DateTime.utc_now()
      start_date = DateTime.add(end_date, -days_back * 24 * 60 * 60, :second)
      
      # Get messages from Gmail
      case get_emails_by_date_range(user, start_date, end_date, max_results: max_results) do
        {:ok, %{messages: messages}} when is_list(messages) ->
          Logger.info("Found #{length(messages)} messages to sync for user #{user.id}")
          
          # Process messages in batches
          {success_count, error_count} = process_messages_batch(user, messages)
          
          # Update sync status with results
          {:ok, updated_sync_status} = Gmail.update_sync_status(sync_status, %{
            sync_status: "completed",
            last_sync_at: DateTime.utc_now(),
            total_emails_processed: (sync_status.total_emails_processed || 0) + success_count,
            last_error_message: if(error_count > 0, do: "#{error_count} emails failed to sync", else: nil)
          })
          
          sync_result = %{
            total_found: length(messages),
            successfully_synced: success_count,
            failed: error_count,
            sync_status: updated_sync_status
          }
          
          Logger.info("Email sync completed for user #{user.id}: #{inspect(sync_result)}")
          {:ok, sync_result}
          
        {:ok, %{messages: nil}} ->
          Logger.info("No new messages found for user #{user.id}")
          
          {:ok, _} = Gmail.update_sync_status(sync_status, %{
            sync_status: "completed",
            last_sync_at: DateTime.utc_now()
          })
          
          {:ok, %{total_found: 0, successfully_synced: 0, failed: 0}}
          
        {:error, reason} ->
          Logger.error("Failed to get emails for user #{user.id}: #{inspect(reason)}")
          
          {:ok, _} = Gmail.update_sync_status(sync_status, %{
            sync_status: "error",
            last_error_message: "Failed to fetch emails: #{inspect(reason)}"
          })
          
          {:error, reason}
      end
    rescue
      error ->
        Logger.error("Exception during email sync for user #{user.id}: #{inspect(error)}")
        
        {:ok, _} = Gmail.update_sync_status(sync_status, %{
          sync_status: "error",
          last_error_message: "Sync failed with exception: #{inspect(error)}"
        })
        
        {:error, "Sync failed with exception: #{inspect(error)}"}
    end
  end

  defp create_initial_sync_status(user_id) do
    {:ok, sync_status} = Gmail.create_sync_status(%{
      user_id: user_id,
      sync_status: "pending",
      total_emails_processed: 0,
      sync_from_date: Date.add(Date.utc_today(), -30),
      sync_to_date: Date.utc_today()
    })
    sync_status
  end

  defp process_messages_batch(user, messages) do
    Logger.info("Processing #{length(messages)} messages for user #{user.id}")
    
    results = Enum.map(messages, fn message ->
      process_single_message(user, message.id)
    end)
    
    # Count successes and failures
    Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {successes, failures} -> {successes + 1, failures}
      {:error, _}, {successes, failures} -> {successes, failures + 1}
    end)
  end

  defp process_single_message(user, message_id) do
    case get_email(user, message_id, format: "full") do
      {:ok, gmail_message} ->
        # Check if email already exists
        case Gmail.get_email_by_gmail_message_id(message_id) do
          nil ->
            # Create new email record
            email_attrs = extract_email_attributes(gmail_message, user.id)
            case Gmail.create_email(email_attrs) do
              {:ok, email} ->
                Logger.debug("Created email #{email.id} for message #{message_id}")
                {:ok, email}
              {:error, changeset} ->
                Logger.error("Failed to create email for message #{message_id}: #{inspect(changeset.errors)}")
                {:error, "Failed to create email"}
            end
          
          existing_email ->
            # Email already exists, optionally update it
            Logger.debug("Email already exists for message #{message_id}")
            {:ok, existing_email}
        end
        
      {:error, reason} ->
        Logger.error("Failed to fetch message #{message_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_email_attributes(gmail_message, user_id) do
    headers = get_headers_map(gmail_message.payload.headers || [])
    
    %{
      gmail_message_id: gmail_message.id,
      subject: Map.get(headers, "subject", ""),
      sender: Map.get(headers, "from", ""),
      recipients: extract_all_recipients(headers),
      content: extract_email_content(gmail_message.payload),
      received_at: parse_gmail_date(Map.get(headers, "date")),
      thread_id: gmail_message.threadId,
      labels: gmail_message.labelIds || [],
      user_id: user_id
    }
  end

  defp get_headers_map(headers) do
    Enum.reduce(headers, %{}, fn %{name: name, value: value}, acc ->
      Map.put(acc, String.downcase(name), value)
    end)
  end

  defp extract_all_recipients(headers) do
    to_recipients = parse_email_addresses(Map.get(headers, "to", ""))
    cc_recipients = parse_email_addresses(Map.get(headers, "cc", ""))
    bcc_recipients = parse_email_addresses(Map.get(headers, "bcc", ""))
    
    %{
      to: to_recipients,
      cc: cc_recipients,
      bcc: bcc_recipients
    }
    |> Jason.encode!()
  end

  defp parse_email_addresses(""), do: []
  defp parse_email_addresses(email_string) do
    email_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_email_content(payload) do
    cond do
      payload.body && payload.body.data ->
        Base.decode64!(payload.body.data, padding: false)
        
      payload.parts ->
        payload.parts
        |> Enum.find(fn part -> part.mimeType in ["text/plain", "text/html"] end)
        |> case do
          %{body: %{data: data}} when is_binary(data) ->
            Base.decode64!(data, padding: false)
          _ ->
            ""
        end
        
      true ->
        ""
    end
  rescue
    _ -> ""
  end

  defp parse_gmail_date(nil), do: DateTime.utc_now()
  defp parse_gmail_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ ->
        # Try parsing common email date formats
        case parse_rfc2822_date(date_string) do
          {:ok, datetime} -> datetime
          _ -> DateTime.utc_now()
        end
    end
  rescue
    _ -> DateTime.utc_now()
  end

  # Simple RFC 2822 date parser for common Gmail date formats
  defp parse_rfc2822_date(date_string) do
    # Remove day of week if present (e.g., "Mon, 01 Jan 2024 12:00:00 +0000")
    cleaned = String.replace(date_string, ~r/^\w+,\s*/, "")
    
    # Try to parse with different timezone formats
    case Regex.run(~r/(\d{1,2})\s+(\w+)\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s*([+-]\d{4}|\w+)/, cleaned) do
      [_, day, month, year, hour, minute, second, tz] ->
        try do
          month_num = month_to_number(month)
          date = Date.new!(String.to_integer(year), month_num, String.to_integer(day))
          time = Time.new!(String.to_integer(hour), String.to_integer(minute), String.to_integer(second))
          naive_dt = NaiveDateTime.new!(date, time)
          
          # Convert to UTC (simplified - assumes common timezones)
          case tz do
            "+0000" -> {:ok, DateTime.from_naive!(naive_dt, "Etc/UTC")}
            "GMT" -> {:ok, DateTime.from_naive!(naive_dt, "Etc/UTC")}
            "UTC" -> {:ok, DateTime.from_naive!(naive_dt, "Etc/UTC")}
            _ -> {:ok, DateTime.from_naive!(naive_dt, "Etc/UTC")} # Default to UTC
          end
        rescue
          _ -> {:error, :invalid_date}
        end
      _ ->
        {:error, :invalid_format}
    end
  end

  defp month_to_number(month) do
    case String.downcase(month) do
      "jan" -> 1
      "feb" -> 2
      "mar" -> 3
      "apr" -> 4
      "may" -> 5
      "jun" -> 6
      "jul" -> 7
      "aug" -> 8
      "sep" -> 9
      "oct" -> 10
      "nov" -> 11
      "dec" -> 12
      _ -> 1 # Default to January
    end
  end

  # Private function to get Gmail connection with valid access token
  defp get_connection(%User{} = user) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      conn = Connection.new(access_token)
      {:ok, conn}
    end
  end

  # Private function to get a valid access token, refreshing if necessary
  defp get_valid_access_token(%User{} = user) do
    if User.has_valid_google_tokens?(user) do
      {:ok, user.google_access_token}
    else
      case user.google_refresh_token do
        nil ->
          {:error, "No Google refresh token available. Please reconnect your Google account."}
        refresh_token ->
          refresh_access_token(user, refresh_token)
      end
    end
  end

  # Private function to refresh the access token
  defp refresh_access_token(%User{} = user, refresh_token) do
    client = OAuth2.Client.new([
      strategy: OAuth2.Strategy.Refresh,
      client_id: Application.get_env(:finpilot, Google)[:client_id],
      client_secret: Application.get_env(:finpilot, Google)[:client_secret],
      site: "https://oauth2.googleapis.com",
      token_url: "https://oauth2.googleapis.com/token",
      params: %{"refresh_token" => refresh_token}
    ])
    |> OAuth2.Client.put_serializer("application/json", Jason)
    
    case OAuth2.Client.get_token(client) do
      {:ok, %OAuth2.Client{token: %OAuth2.AccessToken{access_token: new_access_token, expires_at: expires_at}}} ->
        # Calculate new expiry time
        new_expiry = if expires_at do
          DateTime.from_unix!(expires_at)
        else
          DateTime.add(DateTime.utc_now(), 3600, :second) # Default 1 hour
        end
        
        # Update user with new token
        case Finpilot.Accounts.update_google_tokens(user, new_access_token, refresh_token, new_expiry) do
          {:ok, _updated_user} ->
            {:ok, new_access_token}
          {:error, _changeset} ->
            {:error, "Failed to save refreshed token"}
        end
      {:error, %OAuth2.Response{status_code: status, body: body}} ->
        {:error, "Token refresh failed: #{status} - #{inspect(body)}"}
      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, "OAuth2 error during token refresh: #{inspect(reason)}"}
      {:error, error} ->
        {:error, "Network error during token refresh: #{inspect(error)}"}
    end
  end

  # Private function to build email message in RFC 2822 format
  defp build_email_message(from, to, cc, bcc, subject, body) do
    to_header = if is_list(to), do: Enum.join(to, ", "), else: to
    cc_header = if length(cc) > 0, do: "\r\nCc: #{Enum.join(cc, ", ")}", else: ""
    bcc_header = if length(bcc) > 0, do: "\r\nBcc: #{Enum.join(bcc, ", ")}", else: ""
    
    # Determine content type based on body content
    content_type = if String.contains?(body, "<") and String.contains?(body, ">") do
      "text/html; charset=utf-8"
    else
      "text/plain; charset=utf-8"
    end
    
    """
    From: #{from}
    To: #{to_header}#{cc_header}#{bcc_header}
    Subject: #{subject}
    Content-Type: #{content_type}
    
    #{body}
    """
  end

  # Private function to format date for Gmail query
  defp format_date_for_query(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_string()
    |> String.replace("-", "/")
  end

  defp format_date_for_query(%Date{} = date) do
    date
    |> Date.to_string()
    |> String.replace("-", "/")
  end

  defp format_date_for_query(date_string) when is_binary(date_string) do
    String.replace(date_string, "-", "/")
  end
end