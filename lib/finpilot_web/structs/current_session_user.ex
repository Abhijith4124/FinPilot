defmodule FinpilotWeb.Structs.CurrentSessionUser do
  defstruct [:id, :username, :email, :name, :picture, :verified, :google, :connection_permissions]

  def new_google_tokens(access_token, refresh_token, expiry) do
    %{
      access_token: access_token,
      refresh_token: refresh_token,
      expiry: expiry
    }
  end

  def new_connection_permissions(gmail_read, gmail_write, calendar_read, calendar_write, hubspot) do
    %{
      gmail_read: gmail_read,
      gmail_write: gmail_write,
      calendar_read: calendar_read,
      calendar_write: calendar_write,
      hubspot: hubspot
    }
  end
end
