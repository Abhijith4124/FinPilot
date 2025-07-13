defmodule Finpilot.Services.GmailExample do
  @moduledoc """
  Example usage of the Gmail service.
  This file demonstrates how to use the various Gmail API functions.
  """

  alias Finpilot.Services.Gmail
  alias Finpilot.Accounts.User

  @doc """
  Example: Send a simple email
  """
  def send_simple_email(%User{} = user) do
    Gmail.send_email(
      user,
      "recipient@example.com",
      "Test Subject",
      "Hello, this is a test email!"
    )
  end

  @doc """
  Example: Send an HTML email with CC and BCC
  """
  def send_html_email(%User{} = user) do
    html_body = """
    <html>
      <body>
        <h1>Welcome!</h1>
        <p>This is an <strong>HTML email</strong> with formatting.</p>
        <ul>
          <li>Item 1</li>
          <li>Item 2</li>
        </ul>
      </body>
    </html>
    """

    Gmail.send_email(
      user,
      "recipient@example.com",
      "HTML Email Test",
      html_body,
      cc: ["cc@example.com"],
      bcc: ["bcc@example.com"]
    )
  end

  @doc """
  Example: Get emails from the last 7 days
  """
  def get_recent_emails(%User{} = user) do
    start_date = DateTime.utc_now() |> DateTime.add(-7, :day)
    end_date = DateTime.utc_now()

    Gmail.get_emails_by_date_range(
      user,
      start_date,
      end_date,
      max_results: 50
    )
  end

  @doc """
  Example: Search for emails containing specific text
  """
  def search_emails(%User{} = user, search_term) do
    Gmail.search_emails(
      user,
      "subject:#{search_term} OR from:#{search_term}",
      max_results: 20
    )
  end

  @doc """
  Example: Get new emails since last sync using history ID
  """
  def sync_new_emails(%User{} = user, last_history_id) do
    case Gmail.get_messages_after_history_id(user, last_history_id) do
      {:ok, %{"history" => history_items}} when is_list(history_items) ->
        # Process new messages
        new_messages = 
          history_items
          |> Enum.flat_map(fn item -> Map.get(item, "messagesAdded", []) end)
          |> Enum.map(fn msg -> msg["message"]["id"] end)
        
        {:ok, new_messages}
      {:ok, _} ->
        {:ok, []}
      error ->
        error
    end
  end

  @doc """
  Example: Get full email details
  """
  def get_email_details(%User{} = user, message_id) do
    case Gmail.get_email(user, message_id, format: "full") do
      {:ok, message} ->
        # Extract useful information
        headers = get_in(message, ["payload", "headers"]) || []
        subject = find_header_value(headers, "Subject")
        from = find_header_value(headers, "From")
        to = find_header_value(headers, "To")
        date = find_header_value(headers, "Date")
        
        {:ok, %{
          id: message["id"],
          thread_id: message["threadId"],
          subject: subject,
          from: from,
          to: to,
          date: date,
          snippet: message["snippet"]
        }}
      error ->
        error
    end
  end

  @doc """
  Example: Create and save a draft email
  """
  def create_draft_email(%User{} = user) do
    Gmail.create_draft(
      user,
      "recipient@example.com",
      "Draft Email Subject",
      "This is a draft email that will be saved but not sent."
    )
  end

  @doc """
  Example: Mark email as read by removing UNREAD label
  """
  def mark_email_as_read(%User{} = user, message_id) do
    Gmail.modify_message_labels(
      user,
      message_id,
      [], # add_label_ids
      ["UNREAD"] # remove_label_ids
    )
  end

  @doc """
  Example: Archive email by removing INBOX label
  """
  def archive_email(%User{} = user, message_id) do
    Gmail.modify_message_labels(
      user,
      message_id,
      [], # add_label_ids
      ["INBOX"] # remove_label_ids
    )
  end

  @doc """
  Example: Get user's Gmail profile and current history ID
  """
  def get_user_info(%User{} = user) do
    with {:ok, profile} <- Gmail.get_profile(user),
         {:ok, history_id} <- Gmail.get_current_history_id(user) do
      {:ok, %{
        email: profile["emailAddress"],
        messages_total: profile["messagesTotal"],
        threads_total: profile["threadsTotal"],
        current_history_id: history_id
      }}
    end
  end

  # Helper function to find header value by name
  defp find_header_value(headers, header_name) do
    headers
    |> Enum.find(fn header -> header["name"] == header_name end)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end
end