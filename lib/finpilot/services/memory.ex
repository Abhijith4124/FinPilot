defmodule Finpilot.Services.Memory do
  @moduledoc """
  Memory service for semantic search across tasks and chat messages.
  Provides AI memory capabilities using vector embeddings for contextual retrieval.
  """

  alias Finpilot.Repo
  alias Finpilot.TaskRunner.Task
  alias Finpilot.ChatMessages.ChatMessage
  alias Finpilot.Services.OpenAI
  import Ecto.Query
  import Pgvector.Ecto.Query
  require Logger

  @embedding_model_dimensions 1536  # text-embedding-3-small dimensions
  @default_similarity_threshold 0.7
  @default_limit 10

  @doc """
  Performs semantic search across tasks based on task instructions.

  ## Parameters
  - user_id: The user ID to search tasks for
  - query: The search query text
  - opts: Optional parameters
    - limit: Maximum number of results (default: 10)
    - threshold: Similarity threshold (default: 0.7)
    - include_completed: Include completed tasks (default: true)

  ## Returns
  - {:ok, tasks} - List of similar tasks with similarity scores
  - {:error, reason} - Error during search
  """
  def search_tasks(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)
    include_completed = Keyword.get(opts, :include_completed, true)

    with {:ok, query_embedding} <- OpenAI.generate_embedding_small(query) do
      base_query = from t in Task,
        where: t.user_id == ^user_id,
        where: not is_nil(t.embedding),
        select: %{
          id: t.id,
          task_instruction: t.task_instruction,
          current_stage_summary: t.current_stage_summary,
          is_done: t.is_done,
          context: t.context,
          inserted_at: t.inserted_at,
          updated_at: t.updated_at,
          similarity: cosine_distance(t.embedding, ^query_embedding)
        },
        where: cosine_distance(t.embedding, ^query_embedding) < ^(1 - threshold),
        order_by: cosine_distance(t.embedding, ^query_embedding),
        limit: ^limit

      final_query = if include_completed do
        base_query
      else
        from t in base_query, where: t.is_done == false
      end

      tasks = Repo.all(final_query)
      {:ok, tasks}
    else
      {:error, reason} -> {:error, "Failed to generate embedding: #{reason}"}
    end
  end

  @doc """
  Performs semantic search across chat messages.

  ## Parameters
  - user_id: The user ID to search messages for
  - query: The search query text
  - opts: Optional parameters
    - limit: Maximum number of results (default: 10)
    - threshold: Similarity threshold (default: 0.7)
    - role_filter: Filter by message role ("user", "assistant", "system")
    - session_id: Filter by specific chat session

  ## Returns
  - {:ok, messages} - List of similar messages with similarity scores
  - {:error, reason} - Error during search
  """
  def search_chat_messages(user_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)
    role_filter = Keyword.get(opts, :role_filter)
    session_id = Keyword.get(opts, :session_id)

    with {:ok, query_embedding} <- OpenAI.generate_embedding_small(query) do
      base_query = from m in ChatMessage,
        where: m.user_id == ^user_id,
        where: not is_nil(m.embedding),
        select: %{
          id: m.id,
          message: m.message,
          role: m.role,
          session_id: m.session_id,
          inserted_at: m.inserted_at,
          similarity: cosine_distance(m.embedding, ^query_embedding)
        },
        where: cosine_distance(m.embedding, ^query_embedding) < ^(1 - threshold),
        order_by: cosine_distance(m.embedding, ^query_embedding),
        limit: ^limit

      query_with_role = if role_filter do
        from m in base_query, where: m.role == ^role_filter
      else
        base_query
      end

      final_query = if session_id do
        from m in query_with_role, where: m.session_id == ^session_id
      else
        query_with_role
      end

      messages = Repo.all(final_query)
      {:ok, messages}
    else
      {:error, reason} -> {:error, "Failed to generate embedding: #{reason}"}
    end
  end

  @doc """
  Finds relevant context for AI responses by searching both tasks and chat messages.

  ## Parameters
  - user_id: The user ID to search for
  - query: The search query text
  - opts: Optional parameters
    - task_limit: Maximum number of task results (default: 5)
    - message_limit: Maximum number of message results (default: 5)
    - threshold: Similarity threshold (default: 0.7)

  ## Returns
  - {:ok, %{tasks: tasks, messages: messages}} - Combined search results
  - {:error, reason} - Error during search
  """
  def find_relevant_context(user_id, query, opts \\ []) do
    task_limit = Keyword.get(opts, :task_limit, 5)
    message_limit = Keyword.get(opts, :message_limit, 5)
    threshold = Keyword.get(opts, :threshold, @default_similarity_threshold)

    with {:ok, tasks} <- search_tasks(user_id, query, limit: task_limit, threshold: threshold),
         {:ok, messages} <- search_chat_messages(user_id, query, limit: message_limit, threshold: threshold, role_filter: "user") do
      {:ok, %{tasks: tasks, messages: messages}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Updates the embedding for a specific task.

  ## Parameters
  - task_id: The task ID to update

  ## Returns
  - {:ok, task} - Successfully updated task
  - {:error, reason} - Error during update
  """
  def update_task_embedding(task_id) do
    case Repo.get(Task, task_id) do
      nil ->
        {:error, "Task not found"}

      %Task{task_instruction: task_instruction} = task when is_binary(task_instruction) ->
        case OpenAI.generate_embedding_small(task_instruction) do
          {:ok, embedding} ->
            task
            |> Task.changeset(%{embedding: embedding})
            |> Repo.update()

          {:error, reason} ->
            {:error, "Failed to generate embedding: #{reason}"}
        end

      %Task{} ->
        {:error, "Task instruction is empty or invalid"}
    end
  end

  @doc """
  Updates the embedding for a specific chat message.

  ## Parameters
  - message_id: The message ID to update

  ## Returns
  - {:ok, message} - Successfully updated message
  - {:error, reason} - Error during update
  """
  def update_chat_message_embedding(message_id) do
    case Repo.get(ChatMessage, message_id) do
      nil ->
        {:error, "Message not found"}

      %ChatMessage{message: message_text} = message when is_binary(message_text) ->
        case OpenAI.generate_embedding_small(message_text) do
          {:ok, embedding} ->
            message
            |> ChatMessage.changeset(%{embedding: embedding})
            |> Repo.update()

          {:error, reason} ->
            {:error, "Failed to generate embedding: #{reason}"}
        end

      %ChatMessage{} ->
        {:error, "Message text is empty or invalid"}
    end
  end

  @doc """
  Gets unprocessed tasks that need embeddings generated.

  ## Parameters
  - user_id: The user ID to get tasks for (optional)
  - limit: Maximum number of tasks to return (default: 100)

  ## Returns
  - List of tasks without embeddings
  """
  def get_unprocessed_tasks(user_id \\ nil, limit \\ 100) do
    base_query = from t in Task,
      where: is_nil(t.embedding),
      where: not is_nil(t.task_instruction),
      where: t.task_instruction != "",
      limit: ^limit,
      order_by: [desc: t.inserted_at]

    query = if user_id do
      from t in base_query, where: t.user_id == ^user_id
    else
      base_query
    end

    Repo.all(query)
  end

  @doc """
  Gets unprocessed chat messages that need embeddings generated.

  ## Parameters
  - user_id: The user ID to get messages for (optional)
  - limit: Maximum number of messages to return (default: 100)
  - role_filter: Filter by message role (default: ["user", "assistant"])

  ## Returns
  - List of messages without embeddings
  """
  def get_unprocessed_chat_messages(user_id \\ nil, limit \\ 100, role_filter \\ ["user", "assistant"]) do
    base_query = from m in ChatMessage,
      where: is_nil(m.embedding),
      where: not is_nil(m.message),
      where: m.message != "",
      where: m.role in ^role_filter,
      limit: ^limit,
      order_by: [desc: m.inserted_at]

    query = if user_id do
      from m in base_query, where: m.user_id == ^user_id
    else
      base_query
    end

    Repo.all(query)
  end

  @doc """
  Batch updates embeddings for multiple tasks.

  ## Parameters
  - task_ids: List of task IDs to update

  ## Returns
  - {:ok, {success_count, error_count}} - Batch update results
  """
  def batch_update_task_embeddings(task_ids) when is_list(task_ids) do
    Logger.info("Starting batch update for #{length(task_ids)} tasks")

    results = Enum.map(task_ids, fn task_id ->
      case update_task_embedding(task_id) do
        {:ok, _task} -> :success
        {:error, reason} ->
          Logger.error("Failed to update embedding for task #{task_id}: #{reason}")
          :error
      end
    end)

    success_count = Enum.count(results, &(&1 == :success))
    error_count = Enum.count(results, &(&1 == :error))

    Logger.info("Batch update completed: #{success_count} success, #{error_count} errors")
    {:ok, {success_count, error_count}}
  end

  @doc """
  Batch updates embeddings for multiple chat messages.

  ## Parameters
  - message_ids: List of message IDs to update

  ## Returns
  - {:ok, {success_count, error_count}} - Batch update results
  """
  def batch_update_chat_message_embeddings(message_ids) when is_list(message_ids) do
    Logger.info("Starting batch update for #{length(message_ids)} chat messages")

    results = Enum.map(message_ids, fn message_id ->
      case update_chat_message_embedding(message_id) do
        {:ok, _message} -> :success
        {:error, reason} ->
          Logger.error("Failed to update embedding for message #{message_id}: #{reason}")
          :error
      end
    end)

    success_count = Enum.count(results, &(&1 == :success))
    error_count = Enum.count(results, &(&1 == :error))

    Logger.info("Batch update completed: #{success_count} success, #{error_count} errors")
    {:ok, {success_count, error_count}}
  end
end