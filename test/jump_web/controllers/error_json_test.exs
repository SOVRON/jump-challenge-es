defmodule JumpWeb.ErrorJSONTest do
  use JumpWeb.ConnCase, async: true

  @moduletag :db

  test "renders 404" do
    assert JumpWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert JumpWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
