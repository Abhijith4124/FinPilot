defmodule FinpilotWeb.LandingPageLive.Index do
  use FinpilotWeb, :live_view
  require Logger
  alias Finpilot.Accounts
  alias Finpilot.ChatSessions
  alias Finpilot.ChatMessages
  alias FinpilotWeb.Structs.CurrentSessionUser

  @impl true
  def mount(_params, session, socket) do
    current_user = validate_session_user(session["current_user"])
    {:ok, assign(socket,
      current_user: current_user,
      show_settings: false,
      chat_session: nil,
      messages: [],
      new_message: "",
      loading: false,
      subscribed_session_id: nil
    )}
  end

  @impl true
  def handle_params(%{"id" => session_id}, _uri, socket) do
    # Load existing chat session from URL
    case ChatSessions.get_chat_session(session_id) do
      {:ok, chat_session} ->
        # Load messages for this session
        messages = ChatMessages.list_messages_by_session(session_id)

        # Subscribe to PubSub if not already subscribed
        unless socket.assigns.subscribed_session_id == session_id do
          Phoenix.PubSub.subscribe(Finpilot.PubSub, "chat_session:#{session_id}")
        end

        socket = assign(socket,
          chat_session: chat_session,
          messages: messages,
          subscribed_session_id: session_id
        )
        {:noreply, socket}
      {:error, _} ->
        {:noreply, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # Private function to validate that the session user exists in the database
  defp validate_session_user(nil), do: nil
  defp validate_session_user(%{email: email}) do
    case Accounts.get_user_by_email(email) do
      nil -> nil  # User doesn't exist in database, clear session
      db_user ->
        # Create proper CurrentSessionUser struct with all required fields
        %CurrentSessionUser{
          id: db_user.id,
          username: db_user.username,
          email: db_user.email,
          name: db_user.name,
          picture: db_user.picture,
          verified: db_user.verified,
          connection_permissions: CurrentSessionUser.new_connection_permissions(
            db_user.gmail_read,
            db_user.gmail_write,
            db_user.calendar_read,
            db_user.calendar_write,
            db_user.hubspot
          )
        }
    end
  end
  defp validate_session_user(_), do: nil



  @impl true
  def handle_event("signin_google", _params, socket) do
    case Google.authorize_url() do
      {:ok, redirect_url} ->
        {:noreply, redirect(socket, external: redirect_url)}
      {:error, error} ->
        socket = socket |> put_flash(:error, error)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_settings", _params, socket) do
    {:noreply, assign(socket, :show_settings, !socket.assigns.show_settings)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    # Generate a unique event ID for tracking
    event_id = :crypto.strong_rand_bytes(8) |> Base.encode16()
    Logger.info("[LiveView][#{event_id}] send_message event triggered")
    Logger.info("[LiveView][#{event_id}] Process PID: #{inspect(self())}, Node: #{node()}")

    if socket.assigns.current_user && String.trim(message) != "" do
      user_id = socket.assigns.current_user.id
      trimmed_message = String.trim(message)

      Logger.info("[LiveView][#{event_id}] Processing message for user #{user_id}, message length: #{String.length(trimmed_message)}")

      # Create chat session if it doesn't exist
      {chat_session, socket} = ensure_chat_session(socket, user_id)

      # Add user message to database
      case ChatMessages.create_user_message(chat_session.id, user_id, trimmed_message) do
        {:ok, _user_message} ->
          # Set loading state - the user message will be added via PubSub broadcast
          socket = assign(socket, new_message: "", loading: true)

          # Process message with AI in background
          Logger.info("[LiveView][#{event_id}] Starting Task for AI processing")
          Task.start(fn ->
            Logger.info("[LiveView][#{event_id}] Task started, calling Processor.process_chat")
            Finpilot.Tasks.Processor.process_chat(trimmed_message, user_id, chat_session.id)
          end)

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_message", %{"message" => message}, socket) do
    {:noreply, assign(socket, new_message: message)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    if socket.assigns.current_user do
      {:noreply, push_navigate(socket, to: "/")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("grant_permission", %{"service" => service}, socket) do
    # Handle permission granting logic here
    case service do
      "gmail" ->
        case Google.authorize_url(["https://www.googleapis.com/auth/gmail.modify"]) do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize Gmail: #{error}")
            {:noreply, socket}
        end
      "calendar" ->
        case Google.authorize_url(["https://www.googleapis.com/auth/calendar"]) do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize Calendar: #{error}")
            {:noreply, socket}
        end
      "hubspot" ->
        case Hubspot.authorize_url() do
          {:ok, redirect_url} ->
            {:noreply, redirect(socket, external: redirect_url)}
          {:error, error} ->
            socket = socket |> put_flash(:error, "Failed to authorize HubSpot: #{error}")
            {:noreply, socket}
        end
      _ ->
        {:noreply, socket}
    end
  end

  # Handle AI processing updates - removed :ai_processing_started as polling starts immediately

  @impl true
  def handle_info({:ai_processing_error, reason}, socket) do
    socket = assign(socket, loading: false)
    {:noreply, put_flash(socket, :error, "AI processing failed: #{reason}")}
  end

  # Handle real-time message updates via PubSub
  @impl true
  def handle_info({:new_message, message}, socket) do
    # Add the new message to the current messages list
    updated_messages = socket.assigns.messages ++ [message]

    # If this is an assistant message, turn off loading state
    loading = if message.role == "assistant", do: false, else: socket.assigns.loading

    {:noreply, assign(socket, messages: updated_messages, loading: loading)}
  end

  # Helper function to ensure chat session exists
  defp ensure_chat_session(socket, user_id) do
    case socket.assigns.chat_session do
      nil ->
        # Create new chat session
        case ChatSessions.create_user_chat_session(user_id, "New Chat") do
          {:ok, chat_session} ->
            # Load existing messages for this session
            messages = ChatMessages.list_messages_by_session(chat_session.id)

            # Subscribe to PubSub for real-time updates
            Phoenix.PubSub.subscribe(Finpilot.PubSub, "chat_session:#{chat_session.id}")

            # Update URL without navigation to avoid remounting
            socket = socket
            |> assign(chat_session: chat_session, messages: messages, subscribed_session_id: chat_session.id)
            |> push_patch(to: "/chat/#{chat_session.id}")
            {chat_session, socket}
          {:error, _changeset} ->
            {nil, put_flash(socket, :error, "Failed to create chat session")}
        end
      existing_session ->
        {existing_session, socket}
    end
  end
end
