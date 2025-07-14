defmodule Finpilot.Services.Calendar do
  @moduledoc """
  Google Calendar API service for managing calendar events.
  """

  alias Finpilot.Accounts.User
  alias GoogleApi.Calendar.V3.Api.Events
  alias GoogleApi.Calendar.V3.Connection
  alias GoogleApi.Calendar.V3.Model.Event
  alias OAuth2
  require Logger

  @doc """
  Gets events for a specific month.

  ## Parameters
  - user: User struct with valid Google tokens
  - year: Year (integer)
  - month: Month (integer, 1-12)
  - opts: Optional parameters like calendar_id, max_results

  ## Returns
  - {:ok, events} - List of events for the month
  - {:error, reason} - Error occurred
  """
  def get_monthly_events(%User{} = user, year, month, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      max_results = Keyword.get(opts, :max_results, 250)

      # Calculate start and end of month
      start_date = Date.new!(year, month, 1)
      end_date = Date.end_of_month(start_date)
      
      time_min = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC") |> DateTime.to_iso8601()
      time_max = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC") |> DateTime.to_iso8601()

      case Events.calendar_events_list(conn, calendar_id,
        timeMin: time_min,
        timeMax: time_max,
        maxResults: max_results,
        singleEvents: true,
        orderBy: "startTime"
      ) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to get monthly events: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets events within a specific time frame.

  ## Parameters
  - user: User struct with valid Google tokens
  - start_datetime: Start datetime (DateTime)
  - end_datetime: End datetime (DateTime)
  - opts: Optional parameters like calendar_id, max_results

  ## Returns
  - {:ok, events} - List of events in the time frame
  - {:error, reason} - Error occurred
  """
  def get_events_by_timeframe(%User{} = user, start_datetime, end_datetime, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      max_results = Keyword.get(opts, :max_results, 250)

      time_min = DateTime.to_iso8601(start_datetime)
      time_max = DateTime.to_iso8601(end_datetime)

      case Events.calendar_events_list(conn, calendar_id,
        timeMin: time_min,
        timeMax: time_max,
        maxResults: max_results,
        singleEvents: true,
        orderBy: "startTime"
      ) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to get events by timeframe: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets upcoming events for a user.

  ## Parameters
  - user: User struct with valid Google tokens
  - opts: Optional parameters like calendar_id, max_results, days_ahead

  ## Returns
  - {:ok, events} - List of upcoming events
  - {:error, reason} - Error occurred
  """
  def get_upcoming_events(%User{} = user, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      max_results = Keyword.get(opts, :max_results, 10)
      days_ahead = Keyword.get(opts, :days_ahead, 30)

      time_min = DateTime.utc_now() |> DateTime.to_iso8601()
      time_max = DateTime.utc_now()
                 |> DateTime.add(days_ahead * 24 * 60 * 60, :second)
                 |> DateTime.to_iso8601()

      case Events.calendar_events_list(conn, calendar_id,
        timeMin: time_min,
        timeMax: time_max,
        maxResults: max_results,
        singleEvents: true,
        orderBy: "startTime"
      ) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to get upcoming events: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Creates a new calendar event.

  ## Parameters
  - user: User struct with valid Google tokens
  - event_data: Map containing event details
    - summary: Event title (required)
    - start_datetime: Start datetime (DateTime, required)
    - end_datetime: End datetime (DateTime, required)
    - description: Event description (optional)
    - location: Event location (optional)
    - attendees: List of attendee emails (optional)
  - opts: Optional parameters like calendar_id

  ## Returns
  - {:ok, event} - Created event
  - {:error, reason} - Error occurred
  """
  def create_event(%User{} = user, event_data, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      
      event = build_event_struct(event_data)

      case Events.calendar_events_insert(conn, calendar_id, body: event) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to create event: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Updates an existing calendar event.

  ## Parameters
  - user: User struct with valid Google tokens
  - event_id: ID of the event to update
  - event_data: Map containing updated event details
  - opts: Optional parameters like calendar_id

  ## Returns
  - {:ok, event} - Updated event
  - {:error, reason} - Error occurred
  """
  def update_event(%User{} = user, event_id, event_data, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      
      event = build_event_struct(event_data)

      case Events.calendar_events_update(conn, calendar_id, event_id, body: event) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to update event: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Deletes a calendar event.

  ## Parameters
  - user: User struct with valid Google tokens
  - event_id: ID of the event to delete
  - opts: Optional parameters like calendar_id

  ## Returns
  - {:ok, :deleted} - Event successfully deleted
  - {:error, reason} - Error occurred
  """
  def delete_event(%User{} = user, event_id, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")

      case Events.calendar_events_delete(conn, calendar_id, event_id) do
        {:ok, _} ->
          {:ok, :deleted}
        {:error, error} ->
          {:error, "Failed to delete event: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Gets a specific event by ID.

  ## Parameters
  - user: User struct with valid Google tokens
  - event_id: ID of the event to retrieve
  - opts: Optional parameters like calendar_id

  ## Returns
  - {:ok, event} - Event details
  - {:error, reason} - Error occurred
  """
  def get_event(%User{} = user, event_id, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")

      case Events.calendar_events_get(conn, calendar_id, event_id) do
        {:ok, event} ->
          {:ok, event}
        {:error, error} ->
          {:error, "Failed to get event: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Lists all calendars for the user.

  ## Parameters
  - user: User struct with valid Google tokens

  ## Returns
  - {:ok, calendars} - List of user's calendars
  - {:error, reason} - Error occurred
  """
  def list_calendars(%User{} = user) do
    with {:ok, conn} <- get_connection(user) do
      case GoogleApi.Calendar.V3.Api.CalendarList.calendar_calendar_list_list(conn) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to list calendars: #{inspect(error)}"}
      end
    end
  end

  @doc """
  Searches for events matching a query.

  ## Parameters
  - user: User struct with valid Google tokens
  - query: Search query string
  - opts: Optional parameters like calendar_id, max_results

  ## Returns
  - {:ok, events} - List of matching events
  - {:error, reason} - Error occurred
  """
  def search_events(%User{} = user, query, opts \\ []) do
    with {:ok, conn} <- get_connection(user) do
      calendar_id = Keyword.get(opts, :calendar_id, "primary")
      max_results = Keyword.get(opts, :max_results, 50)

      case Events.calendar_events_list(conn, calendar_id,
        q: query,
        maxResults: max_results,
        singleEvents: true,
        orderBy: "startTime"
      ) do
        {:ok, response} ->
          {:ok, response}
        {:error, error} ->
          {:error, "Failed to search events: #{inspect(error)}"}
      end
    end
  end

  # Private function to build event struct from event data
  defp build_event_struct(event_data) do
    %Event{
      summary: Map.get(event_data, :summary),
      description: Map.get(event_data, :description),
      location: Map.get(event_data, :location),
      start: build_event_datetime(Map.get(event_data, :start_datetime)),
      end: build_event_datetime(Map.get(event_data, :end_datetime)),
      attendees: build_attendees_list(Map.get(event_data, :attendees, [])),
      reminders: %{
        useDefault: Map.get(event_data, :use_default_reminders, true)
      }
    }
  end

  # Private function to build event datetime struct
  defp build_event_datetime(%DateTime{} = datetime) do
    %{
      dateTime: DateTime.to_iso8601(datetime),
      timeZone: "UTC"
    }
  end

  defp build_event_datetime(%Date{} = date) do
    %{
      date: Date.to_iso8601(date)
    }
  end

  defp build_event_datetime(nil), do: nil

  # Private function to build attendees list
  defp build_attendees_list([]), do: []
  defp build_attendees_list(attendees) when is_list(attendees) do
    Enum.map(attendees, fn
      email when is_binary(email) -> %{email: email}
      %{email: _} = attendee -> attendee
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Private function to get Calendar connection with valid access token
  defp get_connection(%User{} = user) do
    with {:ok, access_token} <- get_valid_access_token(user) do
      conn = Connection.new(access_token)
      {:ok, conn}
    end
  end

  # Private function to get a valid access token, refreshing if necessary
  defp get_valid_access_token(%User{} = user) do
    if User.has_valid_google_tokens?(user) do
      {:ok, user.google_access_token}
    else
      case user.google_refresh_token do
        nil ->
          {:error, "No Google refresh token available. Please reconnect your Google account."}
        refresh_token ->
          refresh_access_token(user, refresh_token)
      end
    end
  end

  # Private function to refresh the access token
  defp refresh_access_token(%User{} = user, refresh_token) do
    client = OAuth2.Client.new([
      strategy: OAuth2.Strategy.Refresh,
      client_id: Application.get_env(:finpilot, Google)[:client_id],
      client_secret: Application.get_env(:finpilot, Google)[:client_secret],
      site: "https://oauth2.googleapis.com",
      token_url: "https://oauth2.googleapis.com/token",
      params: %{"refresh_token" => refresh_token}
    ])
    |> OAuth2.Client.put_serializer("application/json", Jason)

    case OAuth2.Client.get_token(client) do
      {:ok, %OAuth2.Client{token: %OAuth2.AccessToken{access_token: new_access_token, expires_at: expires_at}}} ->
        # Calculate new expiry time
        new_expiry = if expires_at do
          DateTime.from_unix!(expires_at)
        else
          DateTime.add(DateTime.utc_now(), 3600, :second) # Default 1 hour
        end

        # Update user with new token
        case Finpilot.Accounts.update_google_tokens(user, new_access_token, refresh_token, new_expiry) do
          {:ok, _updated_user} ->
            {:ok, new_access_token}
          {:error, _changeset} ->
            {:error, "Failed to save refreshed token"}
        end
      {:error, %OAuth2.Response{status_code: status, body: body}} ->
        {:error, "Token refresh failed: #{status} - #{inspect(body)}"}
      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, "OAuth2 error during token refresh: #{inspect(reason)}"}
      {:error, error} ->
        {:error, "Network error during token refresh: #{inspect(error)}"}
    end
  end
end