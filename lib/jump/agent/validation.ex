defmodule Jump.Agent.Validation do
  @moduledoc """
  Tool argument validation using JSON schemas.
  """

  alias ExJsonSchema.Validator
  require Logger

  @doc """
  Validate tool arguments against their JSON schema.
  Returns {:ok, validated_args} or {:error, reason}
  """
  def validate_tool_args(tool_name, args) do
    schema = get_tool_schema(tool_name)

    if schema do
      case Validator.validate(schema, args) do
        :ok ->
          {:ok, args}

        {:error, errors} ->
          Logger.warning("Tool validation failed for #{tool_name}: #{inspect(errors)}")

          case attempt_repair(tool_name, args, errors) do
            {:ok, repaired_args} ->
              Logger.info("Successfully repaired arguments for #{tool_name}")
              {:ok, repaired_args}

            {:error, repair_error} ->
              {:error,
               "Invalid arguments: #{format_validation_errors(errors)}. Repair failed: #{repair_error}"}
          end
      end
    else
      # No schema available, accept as-is
      {:ok, args}
    end
  end

  @doc """
  Get the JSON schema for a tool.
  """
  def get_tool_schema(tool_name) do
    case tool_name do
      "send_email_via_gmail" -> get_email_schema()
      "propose_calendar_times" -> get_propose_times_schema()
      "create_calendar_event" -> get_create_event_schema()
      "hubspot_find_or_create_contact" -> get_contact_schema()
      "hubspot_add_note" -> get_note_schema()
      "search_rag" -> get_search_schema()
      _ -> nil
    end
  end

  # Email tool schema
  defp get_email_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "to" => %{
          "type" => "array",
          "items" => %{"type" => "string", "format" => "email"},
          "minItems" => 1,
          "maxItems" => 50
        },
        "subject" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 200
        },
        "html_body" => %{
          "type" => "string",
          "minLength" => 1
        },
        "text_body" => %{
          "type" => "string"
        },
        "reply_to_message_id" => %{
          "type" => "string"
        },
        "references" => %{
          "type" => "array",
          "items" => %{"type" => "string"}
        }
      },
      "required" => ["to", "subject", "html_body"],
      "additionalProperties" => false
    }
  end

  # Calendar propose times schema
  defp get_propose_times_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "duration_minutes" => %{
          "type" => "integer",
          "minimum" => 15,
          "maximum" => 480
        },
        "window_start" => %{
          "type" => "string",
          "format" => "date-time"
        },
        "window_end" => %{
          "type" => "string",
          "format" => "date-time"
        },
        "min_slots" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 10,
          "default" => 3
        },
        "attendees" => %{
          "type" => "array",
          "items" => %{"type" => "string", "format" => "email"},
          "maxItems" => 20
        },
        "timezone" => %{
          "type" => "string",
          "pattern" => "^[A-Za-z_]+/[A-Za-z_]+$"
        }
      },
      "required" => ["duration_minutes", "window_start", "window_end", "timezone"],
      "additionalProperties" => false
    }
  end

  # Calendar create event schema
  defp get_create_event_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "start" => %{
          "type" => "string",
          "format" => "date-time"
        },
        "end" => %{
          "type" => "string",
          "format" => "date-time"
        },
        "summary" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 200
        },
        "attendees" => %{
          "type" => "array",
          "items" => %{"type" => "string", "format" => "email"},
          "maxItems" => 50
        },
        "description" => %{
          "type" => "string",
          "maxLength" => 2000
        },
        "location" => %{
          "type" => "string",
          "maxLength" => 500
        },
        "conference" => %{
          "type" => "boolean"
        }
      },
      "required" => ["start", "end", "summary"],
      "additionalProperties" => false
    }
  end

  # Contact schema
  defp get_contact_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "email" => %{
          "type" => "string",
          "format" => "email"
        },
        "name" => %{
          "type" => "string",
          "maxLength" => 100
        },
        "properties" => %{
          "type" => "object",
          "additionalProperties" => %{
            "type" => "string"
          },
          "maxProperties" => 20
        }
      },
      "required" => ["email"],
      "additionalProperties" => false
    }
  end

  # Note schema
  defp get_note_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "contact_id" => %{
          "type" => "string",
          "minLength" => 1
        },
        "text" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 2000
        },
        "timestamp" => %{
          "type" => "string",
          "format" => "date-time"
        }
      },
      "required" => ["contact_id", "text"],
      "additionalProperties" => false
    }
  end

  # Search schema
  defp get_search_schema() do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{
          "type" => "string",
          "minLength" => 1,
          "maxLength" => 500
        },
        "search_type" => %{
          "type" => "string",
          "enum" => ["general", "person", "temporal", "contact", "scheduling"],
          "default" => "general"
        },
        "max_results" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => 20,
          "default" => 10
        },
        "time_range" => %{
          "type" => "string",
          "enum" => ["recent", "this_week", "this_month", "this_year"],
          "default" => "recent"
        }
      },
      "required" => ["query"],
      "additionalProperties" => false
    }
  end

  # Attempt to repair common validation errors
  defp attempt_repair(tool_name, args, errors) do
    repaired_args = repair_common_errors(args, errors)

    # Validate the repaired arguments
    schema = get_tool_schema(tool_name)

    if schema do
      case Validator.validate(schema, repaired_args) do
        :ok -> {:ok, repaired_args}
        {:error, _} -> {:error, "Repair failed"}
      end
    else
      {:ok, repaired_args}
    end
  end

  # Repair common validation errors
  defp repair_common_errors(args, errors) do
    Enum.reduce(errors, args, fn error, acc_args ->
      case error do
        %{"type" => "required", "missing" => missing_fields} ->
          # Add default values for missing required fields
          Enum.reduce(missing_fields, acc_args, fn field, acc ->
            Map.put(acc, field, get_default_value(field))
          end)

        %{"type" => "invalid_type", "expected" => expected, "actual" => actual} ->
          # Try to convert to expected type
          repair_type_mismatch(acc_args, error)

        %{"type" => "format", "format" => format} ->
          # Try to fix format issues
          repair_format_issue(acc_args, error)

        _ ->
          acc_args
      end
    end)
  end

  # Get default values for common fields
  defp get_default_value("min_slots"), do: 3
  defp get_default_value("search_type"), do: "general"
  defp get_default_value("max_results"), do: 10
  defp get_default_value("time_range"), do: "recent"
  defp get_default_value("conference"), do: false
  defp get_default_value("text_body"), do: nil
  defp get_default_value("references"), do: []
  defp get_default_value("attendees"), do: []
  defp get_default_value("properties"), do: %{}
  defp get_default_value(_), do: ""

  # Repair type mismatches
  defp repair_type_mismatch(args, %{"instance_path" => path, "expected" => expected}) do
    key = List.last(path)
    value = get_in(args, path)

    cond do
      expected == "array" and is_binary(value) ->
        # Try to split string into array
        updated_value = String.split(value, ",", trim: true)
        put_in(args, path, updated_value)

      expected == "string" and is_list(value) ->
        # Join array into string
        updated_value = Enum.join(value, ", ")
        put_in(args, path, updated_value)

      expected == "integer" and is_binary(value) ->
        # Parse string to integer
        case Integer.parse(value) do
          {int, ""} -> put_in(args, path, int)
          _ -> args
        end

      expected == "boolean" and is_binary(value) ->
        # Parse string to boolean
        bool_value = String.downcase(value) in ["true", "1", "yes", "on"]
        put_in(args, path, bool_value)

      true ->
        args
    end
  end

  defp repair_type_mismatch(args, _), do: args

  # Repair format issues
  defp repair_format_issue(args, %{"instance_path" => path, "format" => "date-time"}) do
    key = List.last(path)
    value = get_in(args, path)

    if is_binary(value) do
      # Try to parse and reformat the datetime
      case DateTime.from_iso8601(value) do
        {:ok, dt, _} ->
          # Ensure proper formatting
          formatted = DateTime.to_iso8601(dt)
          put_in(args, path, formatted)

        {:error, :invalid_format} ->
          # Try to parse common formats
          try_parse_datetime(value, path, args)
      end
    else
      args
    end
  end

  defp repair_format_issue(args, %{"instance_path" => path, "format" => "email"}) do
    key = List.last(path)
    value = get_in(args, path)

    if is_binary(value) do
      # Basic email cleanup
      cleaned = String.trim(value) |> String.downcase()
      put_in(args, path, cleaned)
    else
      args
    end
  end

  defp repair_format_issue(args, _), do: args

  # Try to parse common datetime formats
  defp try_parse_datetime(value, path, args) do
    formats = [
      "{YYYY}-{M}-{D} {h24}:{m}",
      "{M}/{D}/{YYYY} {h12}:{m} {am}",
      "{YYYY}/{M}/{D} {h24}:{m}",
      "{YYYY}-{M}-{D}T{h24}:{m}:00Z"
    ]

    Enum.reduce_while(formats, args, fn format, acc ->
      case Timex.parse(value, format) do
        {:ok, dt} ->
          formatted = DateTime.to_iso8601(dt)
          {:halt, put_in(acc, path, formatted)}

        {:error, _} ->
          {:cont, acc}
      end
    end)
  end

  # Format validation errors for user display
  defp format_validation_errors(errors) when is_list(errors) do
    errors
    |> Enum.map(&format_single_error/1)
    |> Enum.join("; ")
  end

  defp format_validation_errors(error), do: inspect(error)

  defp format_single_error(%{"type" => "required", "missing" => missing}) do
    "Missing required fields: #{Enum.join(missing, ", ")}"
  end

  defp format_single_error(%{
         "type" => "invalid_type",
         "instance_path" => path,
         "expected" => expected
       }) do
    field = List.last(path)
    "Field '#{field}' should be of type #{expected}"
  end

  defp format_single_error(%{"type" => "format", "instance_path" => path, "format" => format}) do
    field = List.last(path)
    "Field '#{field}' has invalid format (expected #{format})"
  end

  defp format_single_error(error), do: inspect(error)
end
