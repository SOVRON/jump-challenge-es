defmodule JumpWeb.Plugs.RequireAuthenticatedUser do
  @moduledoc """
  Plug to require user authentication.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: "/")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{request_path: request_path} = conn) when request_path != "/" do
    put_session(conn, :user_return_to, request_path)
  end

  defp maybe_store_return_to(conn), do: conn
end
