defmodule Finpilot.Services.Gmail do
  @moduledoc """
  Gmail API service for managing emails, sending messages, and retrieving email data.
  """

  alias Finpilot.Accounts.User
  alias GoogleApi.Gmail.V1.Api.Users
  alias GoogleApi.Gmail.V1.Connection
  alias GoogleApi.Gmail.V1.Model.{Message, Draft}
  alias OAuth2

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