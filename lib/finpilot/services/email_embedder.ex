defmodule Finpilot.Services.EmailEmbedder do
  @moduledoc """
  Service for managing email embedding operations.
  This service:
  1. Orchestrates email embedding workflows
  2. Manages Oban worker jobs
  3. Tracks job status and updates sync status
  4. Provides batch processing capabilities
  """

  alias Finpilot.Workers.EmailEmbeddingWorker
  alias Finpilot.Gmail
  alias Finpilot.Gmail.Email
  alias Finpilot.Services.Gmail, as: GmailService
  alias Finpilot.Repo
  import Ecto.Query
  require Logger

  @doc """
  Start email embedding process for a user.

  ## Parameters
  - user_id: The user ID to process emails for
  - opts: Optional parameters
    - batch_size: Number of emails to process per batch (default: 1000)
    - priority: Job priority (default: 0)
    - schedule_in: Delay before starting (default: immediate)

  ## Returns
  - {:ok, job} - Successfully scheduled job
  - {:error, reason} - Error scheduling job
  """
  def start_embedding_process(user_id, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 1000)
    priority = Keyword.get(opts, :priority, 0)
    schedule_in = Keyword.get(opts, :schedule_in, 0)

    Logger.info("Starting email embedding process for user #{user_id}")

    # Check if there are emails to process
    case count_unprocessed_emails(user_id) do
      0 ->
        Logger.info("No unprocessed emails found for user #{user_id}")
        update_sync_status(user_id, :completed, "No emails to process")
        {:ok, :no_emails}

      count ->
        Logger.info("Found #{count} unprocessed emails for user #{user_id}")

        # Update sync status to queued
        update_sync_status(user_id, :queued, "Email embedding job queued")

        # Schedule the worker job
        job_args = %{
          "user_id" => user_id,
          "batch_size" => batch_size
        }

        job =
          EmailEmbeddingWorker.new(job_args,
            priority: priority,
            schedule_in: schedule_in
          )

        case Oban.insert(job) do
          {:ok, job} ->
            Logger.info("Successfully scheduled email embedding job #{job.id} for user #{user_id}")

            # Update sync status with job ID
            update_sync_status(user_id, :queued, "Job #{job.id} scheduled for processing")

            {:ok, job}

          {:error, reason} ->
            error_message = "Failed to schedule email embedding job: #{inspect(reason)}"
            Logger.error(error_message)
            update_sync_status(user_id, :error, error_message)
            {:error, reason}
        end
    end
  end

  @doc """
  Get the status of email embedding process for a user.

  ## Parameters
  - user_id: The user ID to check status for

  ## Returns
  - %{status: status, message: message, progress: progress, job_info: job_info}
  """
  def get_embedding_status(user_id) do
    sync_status = Gmail.get_sync_status_by_user_id(user_id)

    total_emails = count_total_emails(user_id)
    processed_emails = count_processed_emails(user_id)
    unprocessed_emails = count_unprocessed_emails(user_id)

    progress = if total_emails > 0 do
      (processed_emails / total_emails * 100) |> Float.round(2)
    else
      100.0
    end

    # Get active job information
    job_info = get_active_job_info(user_id)

    %{
      status: if(sync_status, do: sync_status.sync_status, else: "unknown"),
      message: if(sync_status, do: sync_status.last_error_message, else: nil),
      last_sync_at: if(sync_status, do: sync_status.last_sync_at, else: nil),
      progress: %{
        total_emails: total_emails,
        processed_emails: processed_emails,
        unprocessed_emails: unprocessed_emails,
        percentage: progress
      },
      job_info: job_info
    }
  end

  @doc """
  Cancel any running email embedding jobs for a user.

  ## Parameters
  - user_id: The user ID to cancel jobs for

  ## Returns
  - {:ok, cancelled_count} - Number of jobs cancelled
  - {:error, reason} - Error cancelling jobs
  """
  def cancel_embedding_jobs(user_id) do
    try do
      # Find and cancel active jobs
      cancelled_jobs =
        Oban.Job
        |> where([j], j.worker == "Finpilot.Workers.EmailEmbeddingWorker")
        |> where([j], j.state in ["available", "executing", "retryable"])
        |> where([j], fragment("?->>'user_id' = ?", j.args, ^to_string(user_id)))
        |> Repo.all()
        |> Enum.map(fn job ->
          Oban.cancel_job(job.id)
        end)
        |> Enum.count(fn result -> match?({:ok, _}, result) end)

      if cancelled_jobs > 0 do
        Logger.info("Cancelled #{cancelled_jobs} email embedding jobs for user #{user_id}")
        update_sync_status(user_id, :cancelled, "#{cancelled_jobs} jobs cancelled")
      end

      {:ok, cancelled_jobs}
    rescue
      error ->
        error_message = "Failed to cancel jobs: #{inspect(error)}"
        Logger.error(error_message)
        {:error, error_message}
    end
  end

  @doc """
  Retry failed email embedding jobs for a user.

  ## Parameters
  - user_id: The user ID to retry jobs for

  ## Returns
  - {:ok, job} - New job scheduled
  - {:error, reason} - Error scheduling retry
  """
  def retry_embedding_process(user_id) do
    Logger.info("Retrying email embedding process for user #{user_id}")

    # Cancel any existing jobs first
    cancel_embedding_jobs(user_id)

    # Start a new embedding process
    start_embedding_process(user_id)
  end

  @doc """
  Sync and embed new emails for a user.
  This will first sync emails from Gmail, then start the embedding process.

  ## Parameters
  - user_id: The user ID to sync and embed emails for
  - opts: Optional parameters passed to both sync and embedding processes

  ## Returns
  - {:ok, {sync_result, embedding_job}} - Both operations successful
  - {:error, reason} - Error in sync or embedding
  """
  def sync_and_embed_emails(user_id, opts \\ []) do
    Logger.info("Starting async sync and embed process for user #{user_id}")

    # Start async email sync from Gmail (this will automatically trigger embedding when done)
    case GmailService.sync_user_emails_async(user_id, opts) do
      {:ok, sync_job} ->
        Logger.info("Email sync job #{sync_job.id} scheduled for user #{user_id}")
        {:ok, sync_job}

      {:error, reason} ->
        error_message = "Failed to schedule email sync: #{reason}"
        Logger.error(error_message)
        update_sync_status(user_id, :error, error_message)
        {:error, error_message}
    end
  end

  # Private functions

  defp count_total_emails(user_id) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> Repo.aggregate(:count, :id)
  end

  defp count_processed_emails(user_id) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> where([e], not is_nil(e.embedding))
    |> Repo.aggregate(:count, :id)
  end

  defp count_unprocessed_emails(user_id) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> where([e], is_nil(e.embedding))
    |> where([e], not is_nil(e.content))
    |> limit(100)  # TODO: Remove this limit after testing
    |> Repo.aggregate(:count, :id)
  end

  defp get_active_job_info(user_id) do
    Oban.Job
    |> where([j], j.worker == "Finpilot.Workers.EmailEmbeddingWorker")
    |> where([j], j.state in ["available", "executing", "retryable"])
    |> where([j], fragment("?->>'user_id' = ?", j.args, ^to_string(user_id)))
    |> order_by([j], desc: j.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      job -> %{
        id: job.id,
        state: job.state,
        inserted_at: job.inserted_at,
        scheduled_at: job.scheduled_at,
        attempted_at: job.attempted_at,
        attempt: job.attempt,
        max_attempts: job.max_attempts
      }
    end
  end

  defp update_sync_status(user_id, status, message) do
    try do
      case Gmail.get_sync_status_by_user_id(user_id) do
        nil ->
          Gmail.create_sync_status(%{
            user_id: user_id,
            sync_status: to_string(status),
            last_sync_at: DateTime.utc_now(),
            last_error_message: if(status in [:error, :partial_error], do: message, else: nil)
          })

        sync_status ->
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
end
