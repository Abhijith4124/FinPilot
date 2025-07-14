defmodule Finpilot.Services.OpenRouter do
  @moduledoc """
  OpenRouter API service for AI completions with tool calling support.
  Provides generic functions for AI interactions including completions and tool calling.
  """

  require Logger

  # Default AI model to use when none is specified
  @default_model "google/gemini-2.0-flash-001"

  # OpenRouter API base URL
  @base_url "https://openrouter.ai/api/v1"

  @doc """
  Calls AI with a specific model..

  ## Returns
  - {:ok, :message, updated_messages} - Normal text response
  - {:ok, :tool_call, updated_messages, tool_calls} - Tool calling response
  - {:error, reason} - Error occurred
  """
  def call_ai(model, messages, opts) do
    with {:ok, api_key} <- get_api_key() do
      system_prompt = Keyword.get(opts, :system_prompt)
      tools = Keyword.get(opts, :tools, [])
      temperature = Keyword.get(opts, :temperature, 0.7)
      max_tokens = Keyword.get(opts, :max_tokens, 4096)

      # Prepare the request body
      request_body = %{
        "model" => model,
        "messages" => prepare_messages(messages, system_prompt),
        "temperature" => temperature,
        "max_tokens" => max_tokens
      }

      # Add tools if provided
      tool_choice_opt = Keyword.get(opts, :tool_choice, "auto")

      request_body = if length(tools) > 0 do
        request_body
        |> Map.put("tools", tools)
        |> Map.put("tool_choice", tool_choice_opt)
      else
        request_body
      end

      # Make the API request
      case make_request(api_key, request_body) do
        {:ok, response} ->
          process_response(response, messages)
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Calls AI with the default model.

  ## Parameters
  - messages: List of message maps with "role" and "content" keys
  - opts: Optional parameters like tools, system_prompt, temperature, etc.

  ## Returns
  - {:ok, :message, updated_messages} - Normal text response
  - {:ok, :tool_call, updated_messages, tool_calls} - Tool calling response
  - {:error, reason} - Error occurred
  """
  def call_ai(messages, opts \\ []) do
    call_ai(@default_model, messages, opts)
  end

  @doc """
  Simple completion function that returns just the AI response text.
  Useful for basic AI interactions without tool calling.

  ## Parameters
  - prompt: The user prompt/question
  - opts: Optional parameters like model, system_prompt, temperature, etc.

  ## Returns
  - {:ok, response_text} - AI response
  - {:error, reason} - Error occurred
  """
  def complete(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    messages = [%{"role" => "user", "content" => prompt}]

    case call_ai(model, messages, opts) do
      {:ok, :message, updated_messages} ->
        # Get the last assistant message
        assistant_message = updated_messages
        |> Enum.reverse()
        |> Enum.find(fn msg -> msg["role"] == "assistant" end)

        case assistant_message do
          %{"content" => content} -> {:ok, content}
          _ -> {:error, "No assistant response found"}
        end
      {:ok, :tool_call, _updated_messages, _tool_calls} ->
        {:error, "Unexpected tool call in simple completion"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private function to get API key from configuration
  defp get_api_key do
    case Application.get_env(:finpilot, OpenRouter)[:api_key] do
      nil -> {:error, "OpenRouter API key not configured"}
      api_key -> {:ok, api_key}
    end
  end

  # Private function to prepare messages with system prompt
  defp prepare_messages(messages, system_prompt) do
    # Add system message if not already present
    case messages do
      [%{"role" => "system"} | _] ->
        messages
      _ ->
        [%{"role" => "system", "content" => system_prompt} | messages]
    end
  end

  # Private function to make HTTP request to OpenRouter API
  defp make_request(api_key, request_body) do
    url = "#{@base_url}/chat/completions"
    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"},
      {"HTTP-Referer", "https://finpilot.ai"},
      {"X-Title", "Finpilot"}
    ]

    body = Jason.encode!(request_body)

    Logger.info("Making OpenRouter API request with model: #{request_body["model"]}")
    Logger.debug("Request body: #{Jason.encode!(request_body, pretty: true)}")

    case Finch.build(:post, url, headers, body) |> Finch.request(Finpilot.Finch) do
      {:ok, %Finch.Response{status: 200, body: response_body}} ->
        Logger.debug("OpenRouter response: #{response_body}")
        case Jason.decode(response_body) do
          {:ok, response} -> {:ok, response}
          {:error, _} -> {:error, "Failed to parse API response"}
        end
      {:ok, %Finch.Response{status: status, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"error" => %{"message" => message}}} ->
            {:error, "OpenRouter API error (#{status}): #{message}"}
          {:ok, %{"error" => error}} when is_binary(error) ->
            {:error, "OpenRouter API error (#{status}): #{error}"}
          _ ->
            {:error, "OpenRouter API error: HTTP #{status}"}
        end
      {:error, reason} ->
        {:error, "Network error: #{inspect(reason)}"}
    end
  end

  # Private function to process API response and determine response type
  defp process_response(response, original_messages) do
    case get_in(response, ["choices", Access.at(0)]) do
      %{"message" => message} ->
        updated_messages = original_messages ++ [message]

        # Check if the response contains tool calls
        case message do
          %{"tool_calls" => tool_calls} when is_list(tool_calls) and length(tool_calls) > 0 ->
            {:ok, :tool_call, updated_messages, tool_calls}
          %{"content" => _content} ->
            {:ok, :message, updated_messages}
          _ ->
            {:error, "Invalid message format in API response"}
        end
      _ ->
        {:error, "Invalid response format from OpenRouter API"}
    end
  end

  @doc """
  Helper function to create a user message.
  """
  def user_message(content) do
    %{"role" => "user", "content" => content}
  end

  @doc """
  Helper function to create an assistant message.
  """
  def assistant_message(content) do
    %{"role" => "assistant", "content" => content}
  end

  @doc """
  Helper function to create a system message.
  """
  def system_message(content) do
    %{"role" => "system", "content" => content}
  end

  @doc """
  Helper function to create a tool result message.
  """
  def tool_message(tool_call_id, content) do
    %{
      "role" => "tool",
      "tool_call_id" => tool_call_id,
      "content" => content
    }
  end

  @doc """
  Helper function to format tool calls for the API.
  Converts tool definitions to OpenAI-compatible format.
  """
  def format_tools(tools) when is_list(tools) do
    # Tools from ToolExecutor already have the correct format with "type" and "function" keys
    # Just return them as-is since they're already properly formatted
    tools
  end
end
