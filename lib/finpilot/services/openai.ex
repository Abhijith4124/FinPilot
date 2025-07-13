defmodule Finpilot.Services.OpenAI do
  @moduledoc """
  OpenAI API service for generating embeddings.
  """

  @base_url "https://api.openai.com/v1"
  @embedding_model_small "text-embedding-3-small"
  @embedding_model_large "text-embedding-3-large"

  @doc """
  Generate embeddings for the given text using OpenAI's text-embedding-3-small model.

  ## Parameters
  - text: The text to generate embeddings for

  ## Returns
  - {:ok, embedding_vector} - Success with embedding vector
  - {:error, reason} - Error with reason
  """
  def generate_embedding_small(text) when is_binary(text) do
    api_key = get_api_key()

    request_body = %{
      "input" => text,
      "model" => @embedding_model_small,
      "encoding_format" => "float"
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case make_request("/embeddings", request_body, headers) do
      {:ok, response} -> process_embedding_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate embeddings for the given text using OpenAI's text-embedding-3-large model.

  ## Parameters
  - text: The text to generate embeddings for

  ## Returns
  - {:ok, embedding_vector} - Success with embedding vector
  - {:error, reason} - Error with reason
  """
  def generate_embedding_large(text) when is_binary(text) do
    api_key = get_api_key()

    request_body = %{
      "input" => text,
      "model" => @embedding_model_large,
      "encoding_format" => "float"
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case make_request("/embeddings", request_body, headers) do
      {:ok, response} -> process_embedding_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate embeddings for multiple texts using the default model (text-embedding-3-small).

  ## Parameters
  - texts: List of texts to generate embeddings for

  ## Returns
  - {:ok, [embedding_vectors]} - Success with list of embedding vectors
  - {:error, reason} - Error with reason
  """
  def generate_embeddings(texts) when is_list(texts) do
    generate_embeddings_small(texts)
  end

  @doc """
  Generate embeddings for multiple texts using OpenAI's text-embedding-3-small model.

  ## Parameters
  - texts: List of texts to generate embeddings for

  ## Returns
  - {:ok, [embedding_vectors]} - Success with list of embedding vectors
  - {:error, reason} - Error with reason
  """
  def generate_embeddings_small(texts) when is_list(texts) do
    api_key = get_api_key()

    request_body = %{
      "input" => texts,
      "model" => @embedding_model_small,
      "encoding_format" => "float"
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case make_request("/embeddings", request_body, headers) do
      {:ok, response} -> process_embeddings_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generate embeddings for multiple texts using OpenAI's text-embedding-3-large model.

  ## Parameters
  - texts: List of texts to generate embeddings for

  ## Returns
  - {:ok, [embedding_vectors]} - Success with list of embedding vectors
  - {:error, reason} - Error with reason
  """
  def generate_embeddings_large(texts) when is_list(texts) do
    api_key = get_api_key()

    request_body = %{
      "input" => texts,
      "model" => @embedding_model_large,
      "encoding_format" => "float"
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    case make_request("/embeddings", request_body, headers) do
      {:ok, response} -> process_embeddings_response(response)
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp get_api_key do
    case Application.get_env(:finpilot, OpenAi)[:api_key] do
      nil -> raise "OPENAI_API_KEY environment variable not set"
      key -> key
    end
  end

  defp make_request(endpoint, body, headers) do
    url = @base_url <> endpoint
    json_body = Jason.encode!(body)

    case Finch.build(:post, url, headers, json_body)
         |> Finch.request(Finpilot.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, response} -> {:ok, response}
          {:error, _} -> {:error, "Failed to parse API response"}
        end
      {:ok, %Finch.Response{status: status, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"error" => %{"message" => message}}} ->
            {:error, "OpenAI API error (#{status}): #{message}"}
          {:ok, %{"error" => error}} when is_binary(error) ->
            {:error, "OpenAI API error (#{status}): #{error}"}
          _ ->
            {:error, "OpenAI API error: HTTP #{status}"}
        end
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  defp process_embedding_response(%{"data" => [%{"embedding" => embedding}]}) do
    {:ok, embedding}
  end
  defp process_embedding_response(_), do: {:error, "Invalid embedding response format"}

  defp process_embeddings_response(%{"data" => data}) when is_list(data) do
    embeddings = Enum.map(data, fn %{"embedding" => embedding} -> embedding end)
    {:ok, embeddings}
  end
  defp process_embeddings_response(_), do: {:error, "Invalid embeddings response format"}
end
