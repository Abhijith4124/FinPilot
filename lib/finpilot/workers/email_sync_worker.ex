defmodule Finpilot.Workers.EmailSyncWorker do
  @moduledoc """
  Oban worker for syncing emails from Gmail in the background.
  This worker:
  1. Fetches emails from Gmail API
  2. Stores them in the database
  3. Updates sync status with progress
  4. Schedules embedding jobs for new emails
  """

  use Oban.Worker, queue: :email_sync

  alias Finpilot.Services.Gmail, as: GmailService
  alias Finpilot.Services.EmailEmbedder
  alias Finpilot.Gmail
  alias Finpilot.Accounts
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    user_id = ensure_binary_id(user_id)
    opts = extract_sync_options(args)

    Logger.info("Starting email sync for user #{user_id}")

    # Update sync status to syncing
    update_sync_status(user_id, :syncing, "Starting email sync")

    try do
      # Get user
      case Accounts.get_user!(user_id) do
        nil ->
          error_message = "User #{user_id} not found"
          Logger.error(error_message)
          update_sync_status(user_id, :error, error_message)
          {:error, error_message}

        user ->
          # Perform the sync
          case GmailService.do_sync_user_emails(user, opts) do
            {:ok, sync_result} ->
              Logger.info("Email sync completed for user #{user_id}: #{inspect(sync_result)}")
              
              # Update sync status to completed
              update_sync_status(user_id, :completed, "Sync completed successfully")
              
              # Schedule embedding job if there are new emails
              if sync_result.successfully_synced > 0 do
                Logger.info("Scheduling embedding job for #{sync_result.successfully_synced} new emails")
                EmailEmbedder.start_embedding_process(user_id)
              end
              
              :ok

            {:error, reason} ->
              error_message = "Email sync failed: #{inspect(reason)}"
              Logger.error(error_message)
              update_sync_status(user_id, :error, error_message)
              {:error, error_message}
          end
      end
    rescue
      error ->
        error_message = "Email sync failed with exception: #{inspect(error)}"
        Logger.error(error_message)
        update_sync_status(user_id, :error, error_message)
        {:error, error_message}
    end
  end

  # Private functions

  defp extract_sync_options(args) do
    [
      max_results: Map.get(args, "max_results", 100),
      days_back: Map.get(args, "days_back", 30)
    ]
  end

  defp update_sync_status(user_id, status, message) do
    try do
      case Gmail.get_sync_status_by_user_id(user_id) do
        nil ->
          # Create new sync status if it doesn't exist
          Gmail.create_sync_status(%{
            user_id: user_id,
            sync_status: to_string(status),
            last_sync_at: DateTime.utc_now(),
            last_error_message: if(status in [:error, :partial_error], do: message, else: nil)
          })

        sync_status ->
          # Update existing sync status
          Gmail.update_sync_status(sync_status, %{
            sync_status: to_string(status),
            last_sync_at: DateTime.utc_now(),
            last_error_message: if(status in [:error, :partial_error], do: message, else: nil)
          })
      end
    rescue
      error ->
        Logger.error("Failed to update sync status for user #{user_id}: #{inspect(error)}")
    end
  end

  defp ensure_binary_id(id) when is_binary(id), do: id
  defp ensure_binary_id(id) when is_integer(id), do: Integer.to_string(id)
  defp ensure_binary_id(id), do: to_string(id)
end