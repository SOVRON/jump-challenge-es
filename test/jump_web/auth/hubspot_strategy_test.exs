defmodule JumpWeb.Auth.HubspotStrategyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  @default_scope "oauth crm.objects.contacts.read crm.objects.contacts.write crm.schemas.contacts.read"

  setup do
    Application.put_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
      client_id: "client-id",
      client_secret: "client-secret",
      site: "https://api.hubapi.com"
    )

    on_exit(fn ->
      Application.delete_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)
    end)

    :ok
  end

  test "handle_request! builds authorize url with scopes param" do
    conn =
      conn(:get, "/auth/hubspot")
      |> fetch_query_params()
      |> put_private(:ueberauth_request_options, request_options())
      |> JumpWeb.Auth.HubspotStrategy.handle_request!()

    [location] = get_resp_header(conn, "location")

    assert location =~ "scopes="
    assert location =~ URI.encode_www_form(@default_scope)
    refute location =~ "scope="
  end

  test "handle_request! honors explicit scope param" do
    conn =
      conn(:get, "/auth/hubspot", %{"scope" => "oauth contacts.read"})
      |> fetch_query_params()
      |> put_private(:ueberauth_request_options, request_options())
      |> JumpWeb.Auth.HubspotStrategy.handle_request!()

    [location] = get_resp_header(conn, "location")

    assert location =~ "scopes="
    assert location =~ "oauth+contacts.read"
  end

  defp request_options do
    %{
      strategy: JumpWeb.Auth.HubspotStrategy,
      strategy_name: "hubspot",
      request_path: "/auth/hubspot",
      callback_path: "/auth/hubspot/callback",
      callback_url: "https://example.com/auth/hubspot/callback",
      request_scheme: "https",
      request_port: 443,
      callback_scheme: "https",
      callback_port: 443,
      options: [
        default_scope: @default_scope,
        request_path: "/auth/hubspot",
        callback_path: "/auth/hubspot/callback"
      ]
    }
  end
end
