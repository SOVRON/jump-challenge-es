defmodule JumpWeb.PageController do
  use JumpWeb, :controller

  def home(conn, _params) do
    if conn.assigns[:current_user] do
      # User is authenticated, redirect to dashboard/chat
      redirect(conn, to: ~p"/app")
    else
      # User is not authenticated, show landing page
      render(conn, :home)
    end
  end
end
