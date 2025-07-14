defmodule Finpilot.Workers.EmailEmbeddingWorker do
  @moduledoc """
  Oban worker for processing email embeddings.
  This worker:
  1. Retrieves emails that need embeddings
  2. Calls OpenAI to generate embeddings
  3. Updates emails with embedding vectors
  4. Updates sync status with progress and errors
  """

  use Oban.Worker, queue: :email_processing

  alias Finpilot.Services.{Gmail, OpenAI}
  alias Finpilot.Gmail
  alias Finpilot.Gmail.Email
  alias Finpilot.Repo
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "batch_size" => batch_size} = _args}) do
    user_id = ensure_binary_id(user_id)
    batch_size = batch_size || 1000

    Logger.info("Starting email embedding processing for user #{user_id}, batch size: #{batch_size}")

    # Update sync status to processing
    update_sync_status(user_id, :processing, "Starting email embedding processing")

    try do
      # Get unprocessed emails for the user
      emails = get_unprocessed_emails(user_id, batch_size)

      if Enum.empty?(emails) do
        Logger.info("No unprocessed emails found for user #{user_id}")
        update_sync_status(user_id, :completed, "No emails to process")
        :ok
      else
        Logger.info("Processing #{length(emails)} emails for user #{user_id}")
        process_emails_batch(emails, user_id, batch_size)
      end
    rescue
      error ->
        error_message = "Email embedding processing failed: #{inspect(error)}"
        Logger.error(error_message)
        update_sync_status(user_id, :error, error_message)
        {:error, error_message}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    # Default batch size if not specified
    perform(%Oban.Job{args: %{"user_id" => user_id, "batch_size" => 1000}})
  end

  # Private functions

  defp get_unprocessed_emails(user_id, batch_size) do
    # TODO: Remove the 1000 email limit after testing
    total_limit = min(batch_size, 1000)

    Email
    |> where([e], e.user_id == ^user_id)
    |> where([e], is_nil(e.embedding))
    |> where([e], not is_nil(e.content))
    |> limit(^total_limit)
    |> order_by([e], e.received_at)
    |> Repo.all()
  end

  defp process_emails_batch(emails, user_id, batch_size) do
    total_emails = length(emails)

    # Prepare texts for batch embedding
    email_texts = Enum.map(emails, &prepare_email_text/1)

    case OpenAI.generate_embeddings_large(email_texts) do
      {:ok, embeddings} ->
        Logger.info("Generated #{length(embeddings)} embeddings for user #{user_id}")

        # Update emails with embeddings
        results = update_emails_with_embeddings(emails, embeddings)

        # Count successes and failures
        {successes, failures} = count_results(results)

        if failures > 0 do
          error_message = "Processed #{successes}/#{total_emails} emails successfully, #{failures} failed"
          Logger.warning(error_message)
          update_sync_status(user_id, :partial_error, error_message)
        else
          success_message = "Successfully processed #{successes} emails"
          Logger.info(success_message)
          update_sync_status(user_id, :completed, success_message)
        end

        # Schedule next batch if there might be more emails
        if total_emails >= 10 do
          schedule_next_batch(user_id, batch_size)
        end

        :ok

      {:error, reason} ->
        error_message = "Failed to generate embeddings: #{reason}"
        Logger.error(error_message)
        update_sync_status(user_id, :error, error_message)
        {:error, error_message}
    end
  end

  defp prepare_email_text(email) do
    # Combine subject and content for embedding
    subject = email.subject || ""
    content = email.content || ""
    sender = email.sender || ""

    "Subject: #{subject}\nFrom: #{sender}\nContent: #{content}"
    |> String.trim()
    |> String.slice(0, 8000) # Limit text length for API
  end

  defp update_emails_with_embeddings(emails, embeddings) do
    emails
    |> Enum.zip(embeddings)
    |> Enum.map(fn {email, embedding} ->
      update_email_embedding(email, embedding)
    end)
  end

  defp update_email_embedding(email, embedding) do
    try do
      email
      |> Email.changeset(%{
        embedding: embedding,
        processed_at: DateTime.utc_now()
      })
      |> Repo.update()

      {:ok, email.id}
    rescue
      error ->
        Logger.error("Failed to update email #{email.id} with embedding: #{inspect(error)}")
        {:error, email.id}
    end
  end

  defp count_results(results) do
    Enum.reduce(results, {0, 0}, fn
      {:ok, _}, {successes, failures} -> {successes + 1, failures}
      {:error, _}, {successes, failures} -> {successes, failures + 1}
    end)
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
            last_error_message: if(status == :error, do: message, else: nil)
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

  defp schedule_next_batch(user_id, batch_size) do
    # Schedule the next batch with a small delay to avoid overwhelming the API
    %{"user_id" => user_id, "batch_size" => batch_size}
    |> new(schedule_in: 5)
    |> Oban.insert()
  end

  defp ensure_binary_id(id) when is_binary(id), do: id
  defp ensure_binary_id(id) when is_integer(id), do: Integer.to_string(id)
  defp ensure_binary_id(id), do: to_string(id)
end
