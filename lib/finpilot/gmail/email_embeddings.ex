defmodule Finpilot.Gmail.EmailEmbeddings do
  @moduledoc """
  Functions for working with email embeddings using pgvector.
  """

  import Ecto.Query
  import Pgvector.Ecto.Query
  alias Finpilot.Repo
  alias Finpilot.Gmail.Email

  @doc """
  Find similar emails using cosine similarity.
  """
  def find_similar_emails(embedding, user_id, limit \\ 5) do
    from(e in Email,
      where: e.user_id == ^user_id and not is_nil(e.embedding),
      order_by: cosine_distance(e.embedding, ^embedding),
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Find similar emails using L2 distance.
  """
  def find_similar_emails_l2(embedding, user_id, limit \\ 5) do
    from(e in Email,
      where: e.user_id == ^user_id and not is_nil(e.embedding),
      order_by: l2_distance(e.embedding, ^embedding),
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Update an email with its embedding vector.
  """
  def update_email_embedding(email_id, embedding_vector) do
    email = Repo.get!(Email, email_id)
    
    email
    |> Email.changeset(%{embedding: embedding_vector, processed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  @doc """
  Get emails that don't have embeddings yet.
  """
  def get_unprocessed_emails(user_id, limit \\ 100) do
    # TODO: Remove the 100 email limit after testing
    actual_limit = min(limit, 100)
    
    from(e in Email,
      where: e.user_id == ^user_id and is_nil(e.embedding),
      order_by: [desc: e.received_at],
      limit: ^actual_limit
    )
    |> Repo.all()
  end

  @doc """
  Search emails by content similarity.
  Returns emails ordered by similarity to the query embedding.
  """
  def semantic_search(query_embedding, user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, 0.8)
    
    from(e in Email,
      where: e.user_id == ^user_id and not is_nil(e.embedding),
      where: cosine_distance(e.embedding, ^query_embedding) < ^threshold,
      order_by: cosine_distance(e.embedding, ^query_embedding),
      limit: ^limit,
      select: %{
        email: e,
        similarity: fragment("1 - (? <=> ?)", e.embedding, ^query_embedding)
      }
    )
    |> Repo.all()
  end
end