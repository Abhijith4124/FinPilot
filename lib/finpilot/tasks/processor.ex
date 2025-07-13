defmodule Finpilot.Tasks.Processor do
  @moduledoc """
  Main interface for triggering AI processing of text/events.
  This module provides a simple API to queue text for AI analysis
  and task creation/management.
  """

  require Logger
  alias Finpilot.Workers.AIProcessingWorker

  @doc """
  Process incoming text through AI analysis.
  
  ## Parameters
  - text: The text content to analyze
  - user_id: ID of the user who owns this text
  - source: Source of the text (e.g., "email", "chat", "webhook")
  - metadata: Additional context data (optional)
  
  ## Examples
  
      iex> Processor.process_text("Schedule a meeting with John tomorrow", user_id, "chat", %{"session_id" => session_id})
      {:ok, %Oban.Job{}}
      
      iex> Processor.process_text(email_content, user_id, "email", %{"sender" => "john@example.com"})
      {:ok, %Oban.Job{}}
  """
  def process_text(text, user_id, source, metadata \\ %{}) do
    # Generate a unique request ID for tracking
    request_id = :crypto.strong_rand_bytes(8) |> Base.encode16()
    Logger.info("[Processor][#{request_id}] Enqueuing AI processing job for user #{user_id}, source: #{source}")
    Logger.info("[Processor][#{request_id}] Process PID: #{inspect(self())}, Node: #{node()}")
    Logger.debug("[Processor][#{request_id}] Text length: #{String.length(text)} characters")
    Logger.debug("[Processor][#{request_id}] Metadata: #{inspect(metadata)}")
    Logger.debug("[Processor][#{request_id}] Stack trace: #{inspect(Process.info(self(), :current_stacktrace))}")
    
    job_args = %{
      "text" => text,
      "user_id" => user_id,
      "source" => source
    }
    |> Map.merge(metadata)
    
    result = job_args
    |> AIProcessingWorker.new()
    |> Oban.insert()
    
    case result do
      {:ok, job} ->
        Logger.info("[Processor][#{request_id}] AI processing job enqueued successfully with ID: #{job.id}")
        result
      {:error, reason} ->
        Logger.error("[Processor][#{request_id}] Failed to enqueue AI processing job: #{inspect(reason)}")
        result
    end
  end

  @doc """
  Process an email through AI analysis.
  Convenience function for email-specific processing.
  The AI will determine if this is a response to an existing task or a new email.
  """
  def process_email(email_content, user_id, email_metadata \\ %{}) do
    metadata = Map.merge(%{
      "sender" => email_metadata["sender"],
      "subject" => email_metadata["subject"],
      "thread_id" => email_metadata["thread_id"],
      "message_id" => email_metadata["message_id"]
    }, email_metadata)
    
    # Let AI determine if this is a response or new content
    process_text(email_content, user_id, "email", metadata)
  end

  @doc """
  Process a chat message from user.
  The AI will determine if this is an instruction or a regular chat message.
  """
  def process_chat(message, user_id, session_id) do
    # Generate a unique request ID for tracking
    chat_request_id = :crypto.strong_rand_bytes(8) |> Base.encode16()
    Logger.info("[Processor][#{chat_request_id}] Processing chat message for user #{user_id}, session: #{session_id}")
    Logger.info("[Processor][#{chat_request_id}] Chat process PID: #{inspect(self())}, Node: #{node()}")
    Logger.debug("[Processor][#{chat_request_id}] Chat stack trace: #{inspect(Process.info(self(), :current_stacktrace))}")
    
    metadata = %{
      "session_id" => session_id,
      "timestamp" => DateTime.utc_now()
    }
    
    result = process_text(message, user_id, "chat", metadata)
    
    case result do
      {:ok, _job} ->
        Logger.info("[Processor][#{chat_request_id}] Chat processing job enqueued successfully")
      {:error, reason} ->
        Logger.error("[Processor][#{chat_request_id}] Failed to enqueue chat processing job: #{inspect(reason)}")
    end
    
    result
  end

  @doc """
  Process a webhook event.
  Convenience function for external system integrations.
  """
  def process_webhook(payload, user_id, webhook_source) do
    text = extract_text_from_webhook(payload)
    metadata = %{
      "webhook_source" => webhook_source,
      "payload" => payload,
      "timestamp" => DateTime.utc_now()
    }
    
    process_text(text, user_id, "webhook", metadata)
  end

  # Extract meaningful text from webhook payload
  defp extract_text_from_webhook(payload) when is_map(payload) do
    # Try to extract text from common webhook fields
    cond do
      payload["message"] -> payload["message"]
      payload["text"] -> payload["text"]
      payload["content"] -> payload["content"]
      payload["body"] -> payload["body"]
      payload["description"] -> payload["description"]
      true -> inspect(payload)
    end
  end

  defp extract_text_from_webhook(payload) when is_binary(payload), do: payload
  defp extract_text_from_webhook(payload), do: inspect(payload)
end