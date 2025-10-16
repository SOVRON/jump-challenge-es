defmodule Jump.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        JumpWeb.Telemetry,
        {Jump.Repo, [if_configured: true]},
        {DNSCluster, query: Application.get_env(:jump, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Jump.PubSub},
        # Start the Oban background job system
        maybe_oban(),
        # Start a worker by calling: Jump.Worker.start_link(arg)
        # {Jump.Worker, arg},
        # Start to serve requests, typically the last entry
        JumpWeb.Endpoint
      ]
      |> Enum.reject(&is_nil/1)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jump.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_oban do
    if Application.get_env(:jump, Oban) do
      {Oban, Application.get_env(:jump, Oban)}
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JumpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
