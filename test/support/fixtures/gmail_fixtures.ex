defmodule Finpilot.GmailFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Finpilot.Gmail` context.
  """

  import Finpilot.AccountsFixtures

  @doc """
  Generate a sync_status.
  """
  def sync_status_fixture(attrs \\ %{}) do
    user = user_fixture()
    
    {:ok, sync_status} =
      attrs
      |> Enum.into(%{
        last_error_message: "some last_error_message",
        last_history_id: "some last_history_id",
        last_sync_at: ~U[2025-07-11 18:36:00Z],
        sync_from_date: ~D[2025-07-11],
        sync_status: "some sync_status",
        sync_to_date: ~D[2025-07-11],
        total_emails_processed: 42,
        user_id: user.id
      })
      |> Finpilot.Gmail.create_sync_status()

    sync_status
  end

  @doc """
  Generate a email.
  """
  def email_fixture(attrs \\ %{}) do
    user = user_fixture()
    
    {:ok, email} =
      attrs
      |> Enum.into(%{
        content: "some content",
        gmail_message_id: "some gmail_message_id",
        labels: "some labels",
        processed_at: ~U[2025-07-11 18:46:00Z],
        received_at: ~U[2025-07-11 18:46:00Z],
        recipients: Jason.encode!(%{to: ["recipient@example.com"], cc: [], bcc: []}),
        sender: "some sender",
        subject: "some subject",
        thread_id: "some thread_id",
        user_id: user.id
      })
      |> Finpilot.Gmail.create_email()

    email
  end
end
