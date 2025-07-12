defmodule Finpilot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FinpilotWeb.Telemetry,
      Finpilot.Repo,
      {DNSCluster, query: Application.get_env(:finpilot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Finpilot.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Finpilot.Finch},
      # Start a worker by calling: Finpilot.Worker.start_link(arg)
      # {Finpilot.Worker, arg},
      # Start to serve requests, typically the last entry
      FinpilotWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Finpilot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FinpilotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
