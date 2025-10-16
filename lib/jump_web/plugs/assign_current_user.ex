defmodule JumpWeb.Plugs.AssignCurrentUser do
  @moduledoc """
  Plug to assign current user from session.
  """

  import Plug.Conn

  alias Jump.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Accounts.get_user(user_id) do
        nil ->
          conn
          |> delete_session(:user_id)
          |> delete_session(:user_email)
          |> assign_user_data(nil)

        user ->
          conn
          |> assign_user_data(user)
      end
    else
      assign_user_data(conn, nil)
    end
  end

  defp assign_user_data(conn, nil) do
    conn
    |> assign(:current_user, nil)
    |> assign(:user_signed_in?, false)
  end

  defp assign_user_data(conn, user) do
    conn
    |> assign(:current_user, user)
    |> assign(:user_signed_in?, true)
  end
end
