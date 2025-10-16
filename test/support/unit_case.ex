defmodule Jump.UnitCase do
  @moduledoc """
  This module defines the setup for unit tests that don't require database access.
  Use this for testing pure functions, validation, and mocked API calls.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Jump.TestHelpers
      import Jump.GmailFixtures
      import Jump.CalendarFixtures
      import Jump.RAGFixtures
    end
  end
end
