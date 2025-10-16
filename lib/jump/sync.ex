defmodule Jump.Sync do
  @moduledoc """
  The Sync context handles synchronization cursors for external services.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.Sync.EmailThread
  alias Jump.Sync.CalendarCursor
  alias Jump.Sync.GmailCursor

  # Email Thread functions
  def list_email_threads(user_id) do
    EmailThread
    |> where([et], et.user_id == ^user_id)
    |> order_by([et], desc: et.last_message_at)
    |> Repo.all()
  end

  def get_email_thread!(id), do: Repo.get!(EmailThread, id)

  def get_email_thread_by_thread_id(user_id, thread_id) do
    Repo.get_by(EmailThread, user_id: user_id, thread_id: thread_id)
  end

  def create_email_thread(attrs \\ %{}) do
    %EmailThread{}
    |> EmailThread.changeset(attrs)
    |> Repo.insert()
  end

  def update_email_thread(%EmailThread{} = email_thread, attrs) do
    email_thread
    |> EmailThread.changeset(attrs)
    |> Repo.update()
  end

  def upsert_email_thread(attrs) do
    %EmailThread{}
    |> EmailThread.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:user_id, :thread_id]
    )
  end

  def delete_email_thread(%EmailThread{} = email_thread) do
    Repo.delete(email_thread)
  end

  def change_email_thread(%EmailThread{} = email_thread, attrs \\ %{}) do
    EmailThread.changeset(email_thread, attrs)
  end

  # Calendar Cursor functions
  def list_calendar_cursors(user_id) do
    CalendarCursor
    |> where([cc], cc.user_id == ^user_id)
    |> Repo.all()
  end

  def get_calendar_cursor!(id), do: Repo.get!(CalendarCursor, id)

  def get_calendar_cursor(user_id, calendar_id) do
    Repo.get_by(CalendarCursor, user_id: user_id, calendar_id: calendar_id)
  end

  def create_calendar_cursor(attrs \\ %{}) do
    %CalendarCursor{}
    |> CalendarCursor.changeset(attrs)
    |> Repo.insert()
  end

  def update_calendar_cursor(%CalendarCursor{} = cursor, attrs) do
    cursor
    |> CalendarCursor.changeset(attrs)
    |> Repo.update()
  end

  def upsert_calendar_cursor(attrs) do
    %CalendarCursor{}
    |> CalendarCursor.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: [:user_id, :calendar_id]
    )
  end

  def delete_calendar_cursor(%CalendarCursor{} = cursor) do
    Repo.delete(cursor)
  end

  def change_calendar_cursor(%CalendarCursor{} = cursor, attrs \\ %{}) do
    CalendarCursor.changeset(cursor, attrs)
  end

  def get_expiring_calendar_cursors(expiring_within_minutes \\ 30) do
    expiration_time = DateTime.add(DateTime.utc_now(), expiring_within_minutes * 60, :second)
    now = DateTime.utc_now()

    CalendarCursor
    |> where([cc], cc.channel_expiration <= ^expiration_time and cc.channel_expiration > ^now)
    |> Repo.all()
  end

  # Gmail Cursor functions
  def list_gmail_cursors do
    Repo.all(GmailCursor)
  end

  def get_gmail_cursor!(id), do: Repo.get!(GmailCursor, id)

  def get_gmail_cursor(user_id) do
    Repo.get_by(GmailCursor, user_id: user_id)
  end

  def create_gmail_cursor(attrs \\ %{}) do
    %GmailCursor{}
    |> GmailCursor.changeset(attrs)
    |> Repo.insert()
  end

  def update_gmail_cursor(%GmailCursor{} = cursor, attrs) do
    cursor
    |> GmailCursor.changeset(attrs)
    |> Repo.update()
  end

  def upsert_gmail_cursor(attrs) do
    %GmailCursor{}
    |> GmailCursor.changeset(attrs)
    |> Repo.insert(
      on_conflict: :replace_all,
      conflict_target: :user_id
    )
  end

  def delete_gmail_cursor(%GmailCursor{} = cursor) do
    Repo.delete(cursor)
  end

  def change_gmail_cursor(%GmailCursor{} = cursor, attrs \\ %{}) do
    GmailCursor.changeset(cursor, attrs)
  end

  def get_expiring_gmail_cursors(expiring_within_minutes \\ 30) do
    expiration_time = DateTime.add(DateTime.utc_now(), expiring_within_minutes * 60, :second)
    now = DateTime.utc_now()

    GmailCursor
    |> where([gc], gc.watch_expiration <= ^expiration_time and gc.watch_expiration > ^now)
    |> Repo.all()
  end
end
