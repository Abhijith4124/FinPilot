defmodule FinpilotWeb.Structs.CurrentSessionUser do
  defstruct [:id, :username, :email, :name, :picture, :verified, :google]

  def new_google_tokens(access_token, refresh_token, expiry) do
    %{
      access_token: access_token,
      refresh_token: refresh_token,
      expiry: expiry
    }
  end
end
