defmodule Finpilot.GmailTest do
  use Finpilot.DataCase

  alias Finpilot.Gmail

  describe "gmail_sync_status" do
    alias Finpilot.Gmail.SyncStatus

    import Finpilot.GmailFixtures

    @invalid_attrs %{last_history_id: nil, last_sync_at: nil, sync_status: nil, total_emails_processed: nil, last_error_message: nil, sync_from_date: nil, sync_to_date: nil}

    test "list_gmail_sync_status/0 returns all gmail_sync_status" do
      sync_status = sync_status_fixture()
      assert Gmail.list_gmail_sync_status() == [sync_status]
    end

    test "get_sync_status!/1 returns the sync_status with given id" do
      sync_status = sync_status_fixture()
      assert Gmail.get_sync_status!(sync_status.id) == sync_status
    end

    test "create_sync_status/1 with valid data creates a sync_status" do
      valid_attrs = %{last_history_id: "some last_history_id", last_sync_at: ~U[2025-07-11 18:36:00Z], sync_status: "some sync_status", total_emails_processed: 42, last_error_message: "some last_error_message", sync_from_date: ~D[2025-07-11], sync_to_date: ~D[2025-07-11]}

      assert {:ok, %SyncStatus{} = sync_status} = Gmail.create_sync_status(valid_attrs)
      assert sync_status.last_history_id == "some last_history_id"
      assert sync_status.last_sync_at == ~U[2025-07-11 18:36:00Z]
      assert sync_status.sync_status == "some sync_status"
      assert sync_status.total_emails_processed == 42
      assert sync_status.last_error_message == "some last_error_message"
      assert sync_status.sync_from_date == ~D[2025-07-11]
      assert sync_status.sync_to_date == ~D[2025-07-11]
    end

    test "create_sync_status/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Gmail.create_sync_status(@invalid_attrs)
    end

    test "update_sync_status/2 with valid data updates the sync_status" do
      sync_status = sync_status_fixture()
      update_attrs = %{last_history_id: "some updated last_history_id", last_sync_at: ~U[2025-07-12 18:36:00Z], sync_status: "some updated sync_status", total_emails_processed: 43, last_error_message: "some updated last_error_message", sync_from_date: ~D[2025-07-12], sync_to_date: ~D[2025-07-12]}

      assert {:ok, %SyncStatus{} = sync_status} = Gmail.update_sync_status(sync_status, update_attrs)
      assert sync_status.last_history_id == "some updated last_history_id"
      assert sync_status.last_sync_at == ~U[2025-07-12 18:36:00Z]
      assert sync_status.sync_status == "some updated sync_status"
      assert sync_status.total_emails_processed == 43
      assert sync_status.last_error_message == "some updated last_error_message"
      assert sync_status.sync_from_date == ~D[2025-07-12]
      assert sync_status.sync_to_date == ~D[2025-07-12]
    end

    test "update_sync_status/2 with invalid data returns error changeset" do
      sync_status = sync_status_fixture()
      assert {:error, %Ecto.Changeset{}} = Gmail.update_sync_status(sync_status, @invalid_attrs)
      assert sync_status == Gmail.get_sync_status!(sync_status.id)
    end

    test "delete_sync_status/1 deletes the sync_status" do
      sync_status = sync_status_fixture()
      assert {:ok, %SyncStatus{}} = Gmail.delete_sync_status(sync_status)
      assert_raise Ecto.NoResultsError, fn -> Gmail.get_sync_status!(sync_status.id) end
    end

    test "change_sync_status/1 returns a sync_status changeset" do
      sync_status = sync_status_fixture()
      assert %Ecto.Changeset{} = Gmail.change_sync_status(sync_status)
    end
  end

  describe "emails" do
    alias Finpilot.Gmail.Email

    import Finpilot.GmailFixtures

    @invalid_attrs %{labels: nil, gmail_message_id: nil, subject: nil, sender: nil, recipients: nil, content: nil, received_at: nil, thread_id: nil, processed_at: nil}

    test "list_emails/0 returns all emails" do
      email = email_fixture()
      assert Gmail.list_emails() == [email]
    end

    test "get_email!/1 returns the email with given id" do
      email = email_fixture()
      assert Gmail.get_email!(email.id) == email
    end

    test "create_email/1 with valid data creates a email" do
      valid_attrs = %{labels: "some labels", gmail_message_id: "some gmail_message_id", subject: "some subject", sender: "some sender", recipients: Jason.encode!(%{to: ["test@example.com"], cc: [], bcc: []}), content: "some content", received_at: ~U[2025-07-11 18:46:00Z], thread_id: "some thread_id", processed_at: ~U[2025-07-11 18:46:00Z]}

      assert {:ok, %Email{} = email} = Gmail.create_email(valid_attrs)
      assert email.labels == "some labels"
      assert email.gmail_message_id == "some gmail_message_id"
      assert email.subject == "some subject"
      assert email.sender == "some sender"
      assert email.recipients == Jason.encode!(%{to: ["test@example.com"], cc: [], bcc: []})
      assert email.content == "some content"
      assert email.received_at == ~U[2025-07-11 18:46:00Z]
      assert email.thread_id == "some thread_id"
      assert email.processed_at == ~U[2025-07-11 18:46:00Z]
    end

    test "create_email/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Gmail.create_email(@invalid_attrs)
    end

    test "update_email/2 with valid data updates the email" do
      email = email_fixture()
      update_attrs = %{labels: "some updated labels", gmail_message_id: "some updated gmail_message_id", subject: "some updated subject", sender: "some updated sender", recipients: Jason.encode!(%{to: ["updated@example.com"], cc: ["cc@example.com"], bcc: []}), content: "some updated content", received_at: ~U[2025-07-12 18:46:00Z], thread_id: "some updated thread_id", processed_at: ~U[2025-07-12 18:46:00Z]}

      assert {:ok, %Email{} = email} = Gmail.update_email(email, update_attrs)
      assert email.labels == "some updated labels"
      assert email.gmail_message_id == "some updated gmail_message_id"
      assert email.subject == "some updated subject"
      assert email.sender == "some updated sender"
      assert email.recipients == Jason.encode!(%{to: ["updated@example.com"], cc: ["cc@example.com"], bcc: []})
      assert email.content == "some updated content"
      assert email.received_at == ~U[2025-07-12 18:46:00Z]
      assert email.thread_id == "some updated thread_id"
      assert email.processed_at == ~U[2025-07-12 18:46:00Z]
    end

    test "update_email/2 with invalid data returns error changeset" do
      email = email_fixture()
      assert {:error, %Ecto.Changeset{}} = Gmail.update_email(email, @invalid_attrs)
      assert email == Gmail.get_email!(email.id)
    end

    test "delete_email/1 deletes the email" do
      email = email_fixture()
      assert {:ok, %Email{}} = Gmail.delete_email(email)
      assert_raise Ecto.NoResultsError, fn -> Gmail.get_email!(email.id) end
    end

    test "change_email/1 returns a email changeset" do
      email = email_fixture()
      assert %Ecto.Changeset{} = Gmail.change_email(email)
    end
  end
end
