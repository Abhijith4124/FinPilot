defmodule Finpilot.Workers.ChatAssistant do
  use Oban.Worker,
    queue: :chat_assistant

  alias Finpilot.ChatAssistant
  alias Finpilot.Services.OpenRouter
  alias Finpilot.Workers.ToolExecutor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "session_id" => session_id, "message" => message}
      }) do

    case call_ai(user_id, session_id, message) do
      {:ok, tool_calls} -> "run_tool_calls(tool_calls)"
      {:error, error_message} -> "create_assistant_message()"
      _ ->
    end
  end

  defp call_ai(user_id, session_id, message) do
    user_id = ensure_binary_id(user_id)
    session_id = ensure_binary_id(session_id)

    tools = get_tool_definitions() ++ ToolExecutor.get_tool_definitions()

    messages = [OpenRouter.user_message(message)]

    Logger.info(messages)

    ai_call_result =
      OpenRouter.call_ai(messages,
        tools: OpenRouter.format_tools(tools),
        system_prompt: build_system_prompt()
      )

    return_result = case ai_call_result do
      {:ok, :tool_call, _updated_messages, tool_calls} ->
        Logger.info(
          "[AIProcessingWorker] AI call successful, received #{length(tool_calls)} tool calls"
        )
        {:ok, tool_calls}
      {:error, reason} ->
        Logger.error("[AIProcessingWorker] AI call failed: #{reason}")
        {:error, "AI Returned Non Tool Call Result"}
      other ->
        Logger.warning("[AIProcessingWorker] Unexpected AI response: #{inspect(other)}")
         {:error, "Unexpected Error"}
    end
    return_result
  end

  defp create_assistant_message(args, user_id, _context) do
    message_params = %{
      user_id: user_id,
      role: "assistant",
      message: args["message"],
      session_id: args["session_id"]
    }

    case ChatMessages.create_chat_message(message_params) do
    {:ok, message} ->
      Logger.info("[AIProcessingWorker] Assistant message created: #{message.id}")
      {:ok, %{message_id: message.id, content: message.message}}
    {:error, changeset} ->
      Logger.error("[AIProcessingWorker] Failed to create assistant message: #{inspect(changeset.errors)}")
      {:error, "Failed to create message: #{inspect(changeset.errors)}"}
    end
  end

  defp ensure_binary_id(user_id) when is_binary(user_id), do: user_id
  defp ensure_binary_id(user_id), do: to_string(user_id)

  defp get_tool_definitions do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_task",
          "description" =>
            "Create a new task for tool calling and multi step tool calling process",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "task_instruction" => %{
                "type" => "string",
                "description" =>
                  "Detailed instruction describing what the task should achieve to be considered complete"
              },
              "current_summary" => %{
                "type" => "string",
                "description" =>
                  "Summary of what has been done so far (initially just the starting summary)",
                "default" => ""
              },
              "next_instruction" => %{
                "type" => "string",
                "description" =>
                  "Specific instruction for what the AI should do when processing this task next"
              },
              "context" => %{
                "type" => "object",
                "description" => "Additional context and metadata for the task",
                "default" => %{}
              }
            },
            "required" => ["task_instruction", "next_instruction"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_assistant_message",
          "description" => "Send a message to the user as the AI assistant",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "message" => %{
                "type" => "string",
                "description" => "The message content to send to the user"
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Optional chat session ID to associate the message with"
              }
            },
            "required" => ["message"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "create_system_message",
          "description" => "Create a system message for logging or internal communication",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "message" => %{
                "type" => "string",
                "description" => "The system message content"
              },
              "session_id" => %{
                "type" => "string",
                "description" => "Optional chat session ID to associate the message with"
              }
            },
            "required" => ["message"]
          }
        }
      }
    ]
  end

  def build_system_prompt do
    """
    You are FinPilot, an intelligent AI assistant designed to act as a professional financial advisor assistant. Your role is to analyze incoming text, execute operations using tools, and respond **only** with tool calls. You must not provide direct text responses unless explicitly routed through the `create_assistant_message` or `create_system_message` tools. You are capable of:

    - Writing professional emails using the `write_email` tool.
    - Analyzing emails and providing summaries or searching through email content using the `analyze_email` or `search_email` tools.
    - Updating and scheduling events on a calendar using the `schedule_calendar_event` or `update_calendar_event` tools.
    - Creating and updating contacts in HubSpot CRM using the `create_hubspot_contact` or `update_hubspot_contact` tools.
    - Following ongoing instructions (e.g., automatically forwarding emails or creating HubSpot contacts) using appropriate tools.
    - Executing background tasks, potentially returning multiple tool calls as needed.

    **Response Rules**:
    - **All** responses must be tool calls. Do not return plain text or conversational responses.
    - To send a message to the user (e.g., a response, clarification, or financial advice), use the `create_assistant_message` tool with the message content.
    - To send a system message (e.g., "Email sent to user" or "Task completed"), use the `create_system_message` tool with the message content.
    - Analyze the input to determine which tools to call and execute tasks efficiently.
    - If the input is unclear, use the `create_assistant_message` tool to request clarification in a professional, client-focused tone.
    - For ongoing instructions (e.g., "when I get an email from someone, forward it"), apply them consistently and call the relevant tools (e.g., `forward_email` or `create_hubspot_contact`).

    **Dynamic Tool-Calling Instructions:**
    {TOOL_CALL_INSTRUCTIONS}

    If no specific tool-calling instructions are provided, determine the appropriate tools based on the user's request and context. Call multiple tools in a single response if necessary, ensuring all tool calls are relevant and executed in the correct order to fulfill the user's intent. Maintain a professional and financial advisor-appropriate approach in all actions.
    """
  end
end
