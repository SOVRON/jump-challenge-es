# Compilation Errors and Warnings Documentation

This document catalogues all unique compilation errors and warnings found in the current build output. Each error category includes affected files and recommended fixes.

---

## 1. Google Calendar API - Undefined Functions

### Issue
Google Calendar API methods are being called with incorrect function names and signatures (verified against hexdocs.pm google_api_calendar v0.23.1).

### Verified Correct Function Signatures

**CalendarList API** (`GoogleApi.Calendar.V3.Api.CalendarList`):
- `calendar_calendar_list_list(connection, optional_params \\ [], opts \\ [])` - List calendars
- `calendar_calendar_list_get(connection, calendar_id, optional_params \\ [], opts \\ [])` - Get specific calendar
- `calendar_calendar_list_insert(connection, optional_params \\ [], opts \\ [])`
- `calendar_calendar_list_delete(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendar_list_update(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendar_list_patch(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendar_list_watch(connection, optional_params \\ [], opts \\ [])`

**Calendars API** (`GoogleApi.Calendar.V3.Api.Calendars`):
- `calendar_calendars_get(connection, calendar_id, optional_params \\ [], opts \\ [])` - Get calendar metadata
- `calendar_calendars_insert(connection, optional_params \\ [], opts \\ [])`
- `calendar_calendars_update(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendars_patch(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendars_delete(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_calendars_clear(connection, calendar_id, optional_params \\ [], opts \\ [])`

**Events API** (`GoogleApi.Calendar.V3.Api.Events`):
- `calendar_events_list(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_events_insert(connection, calendar_id, optional_params \\ [], opts \\ [])`
- `calendar_events_update(connection, calendar_id, event_id, optional_params \\ [], opts \\ [])`
- `calendar_events_delete(connection, calendar_id, event_id, optional_params \\ [], opts \\ [])`
- `calendar_events_get(connection, calendar_id, event_id, optional_params \\ [], opts \\ [])`
- `calendar_events_watch(connection, calendar_id, optional_params \\ [], opts \\ [])`

**Freebusy API** (`GoogleApi.Calendar.V3.Api.Freebusy`):
- `calendar_freebusy_query(connection, optional_params \\ [], opts \\ [])`

**Channels API** (`GoogleApi.Calendar.V3.Api.Channels`):
- `calendar_channels_stop(connection, optional_params \\ [], opts \\ [])`

### Errors to Fix
- `GoogleApi.Calendar.V3.Api.CalendarList.calendar_list(conn, params)` → `calendar_calendar_list_list(conn, [])`
- `GoogleApi.Calendar.V3.Api.Calendars.calendars_get(conn, "primary")` → `calendar_calendars_get(conn, "primary")`
- `GoogleApi.Calendar.V3.Api.Freebusy.freebusy_query(conn, body: ...)` → `calendar_freebusy_query(conn, body: ...)`
- All Events API calls need prefix `calendar_` and use 3/4 parameters not 3 alone
- `GoogleApi.Calendar.V3.Api.Channels.stop(conn, body: ...)` → `calendar_channels_stop(conn, body: ...)`

### Files to Fix
- `lib/jump/calendar/client.ex` - list_calendars, get_primary_calendar, get_free_busy, etc.
- `lib/jump/calendar/events.ex` - get_event, create_event, update_event, delete_event, respond_to_invitation
- `lib/jump/calendar/proposals.ex` - Events API calls

---

## 2. Google Gmail API - Undefined Functions

### Issue
Gmail API methods have incorrect function names and missing required parameters.

### Errors
- `GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_get/2` is undefined
  - **Should be**: `gmail_users_messages_get/3` with `user_id` parameter
  - **Files**: `lib/jump/gmail/client.ex:102`

- `GoogleApi.Gmail.V1.Api.Users.gmail_users_threads_get/2` is undefined
  - **Should be**: `gmail_users_threads_get/3` with `user_id` parameter
  - **Files**: `lib/jump/gmail/client.ex:254`

### Fix Strategy
Gmail API methods require the user ID as an explicit parameter. Update signatures to:
```elixir
GoogleApi.Gmail.V1.Api.Users.gmail_users_messages_get(conn, user_id, message_id, opts)
```

---

## 3. DateTime Module - Undefined/Private Functions

### Issue
Elixir's DateTime module doesn't have some methods being called, and some are private.

### Errors
- `DateTime.from_iso8601!/1` is undefined (should use `/2` or `/3`)
  - **Files**: 
    - `lib/jump/agent/tools.ex:162, 163, 250, 251, 398`
  - **Fix**: Use `DateTime.from_iso8601/1` or `DateTime.from_iso8601/2` and handle the tuple return

- `DateTime.now_utc/0` is undefined
  - **Should be**: `DateTime.now(:utc)` or `DateTime.utc_now()` in older versions
  - **Files**:
    - `lib/jump/rag/retriever.ex:560, 565, 579, 580, 583, 584`
    - `lib/jump/rag/tools.ex` (multiple locations)

- `DateTime.beginning_of_day/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/retriever.ex:579, 580`
    - `lib/jump/rag/tools.ex:633, 634, 638, 639, 643, 644`

- `DateTime.end_of_day/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/retriever.ex:579, 580`

- `DateTime.beginning_of_week/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/retriever.ex:583, 584`
    - `lib/jump/rag/tools.ex:633, 634, 907, 908`

- `DateTime.end_of_week/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/retriever.ex:584`
    - `lib/jump/rag/tools.ex:634, 908`

- `DateTime.beginning_of_month/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/retriever.ex` (not shown but referenced)
    - `lib/jump/rag/tools.ex:638, 912`

- `DateTime.end_of_month/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/tools.ex:639, 913`

- `DateTime.beginning_of_year/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/tools.ex:643, 921`

- `DateTime.end_of_year/1` is undefined
  - **Should be**: Use Date module or custom logic
  - **Files**:
    - `lib/jump/rag/tools.ex:644, 922`

### Fix Strategy
These functions don't exist in Elixir's DateTime module. Use custom helpers or the Timex library for advanced date operations. Create utility functions or use Date module directly.

---

## 4. Date Module - Undefined Functions

### Issue
`Date.to_date/1` doesn't exist - DateTime is already a date when converted.

### Errors
- `Date.to_date/1` is undefined or private
  - **Files**:
    - `lib/jump/calendar/proposals.ex:352, 358`
    - `lib/jump/calendar/free_busy.ex:249, 250, 440`

### Fix Strategy
Remove `Date.to_date()` calls. If you have a DateTime, use:
```elixir
DateTime.to_date(datetime)
```

---

## 5. Deprecated Logger Methods

### Issue
`Logger.warn/1` is deprecated and should be replaced with `Logger.warning/2`.

### Affected Files
- `lib/jump/agent/validation.ex:22`
- `lib/jump/agent/tasks.ex:61, 69, 85, 228, 338, 350, 362`
- `lib/jump/workers/embed_chunk.ex:127`
- `lib/jump/workers/import_gmail_mailbox.ex:109, 137`
- `lib/jump/workers/gmail_history_sync.ex:208`

### Fix Strategy
Replace all instances of `Logger.warn("message")` with `Logger.warning("message")` or `Logger.warning("message", [])` for additional context.

---

## 6. Logger.error/2 and Logger.warning/2 Undefined

### Issue
These methods need to be invoked as macros with proper requires.

### Errors
- `Logger.error/2` is undefined or private (macro not required)
  - **Files**: `lib/jump/agent.ex:53`

- `Logger.warning/2` is undefined or private (macro not required)
  - **Files**: `lib/jump_web/live/chat_live.ex:300, 307`

### Fix Strategy
Add `require Logger` at the top of files that use Logger macros.

---

## 7. Swoosh Email API - Undefined Methods

### Issue
Swoosh.Email doesn't have the methods being called with those signatures.

### Errors
- `Swoosh.Email.render/1` is undefined
  - **Should be**: Use `Swoosh.Email.Renderer.render/1` or check Swoosh version
  - **Files**: `lib/jump/gmail/composer.ex:65`

- `Swoosh.Email.get_html_body/1` is undefined
  - **Should be**: Access the email struct directly: `email.html_body`
  - **Files**: `lib/jump/gmail/composer.ex:322, 342`

- `Swoosh.Email.get_text_body/1` is undefined
  - **Should be**: Access the email struct directly: `email.text_body`
  - **Files**: `lib/jump/gmail/composer.ex:323, 361`

### Fix Strategy
Update to use proper Swoosh API or direct struct access.

---

## 8. Missing Module Implementations

### Issue
Modules or functions that don't exist yet.

### Errors
- `Jump.CRM.HubSpot.Client.get_or_create_contact/3` is undefined
  - **Files**: `lib/jump/agent/tools.ex:334`

- `Jump.CRM.HubSpot.Client.create_contact_note/3` is undefined
  - **Files**: `lib/jump/agent/tools.ex:401`

- `Jump.Gmail.Composer.send_email/7` is undefined
  - **Files**: `lib/jump/agent/tools.ex:76`

- `Jump.Calendar.Proposals.get_proposals/7` is undefined
  - **Should be**: `generate_proposals/1` or `generate_proposals/2`
  - **Files**: `lib/jump/agent/tools.ex:171`

- `Jump.Calendar.Events.create_event/8` is undefined
  - **Should be**: `create_event/2` or `create_event/3`
  - **Files**: `lib/jump/agent/tools.ex:259`

- `Jump.Accounts.get_user/1` is undefined
  - **Should be**: `get_user!/1` or `get_user_by_email/1`
  - **Files**: `lib/jump/calendar/events.ex:304`

- `Email` module is not available
  - **Files**: `lib/jump/workers/send_email_job.ex:160, 161, 162`

### Fix Strategy
Implement missing modules or update function calls to use existing functions.

---

## 9. Type Mismatches

### Issue
Passing wrong types to functions expecting specific types.

### Errors
- `length(results)` expects a list but got `{:error or :ok, term()}`
  - **Files**: `lib/jump/agent/context.ex:65`
  - **Issue**: `search_and_retrieve` returns a tuple, not a list
  - **Fix**: Handle the `{:ok, results}` tuple before calling `length()`

---

## 10. Unused Variables and Aliases

### Issue
Variables or imports declared but never used in code.

### Common Unused Variables
- `timezone` - declared but not used (appears in multiple files)
- `user_id` - not used in some context functions
- `message`, `chunk`, `text`, `key` - various unused parameters
- `query_text`, `query_lower`, `query` - unused in some search functions
- `max_results`, `event_name`, `opts` - not used in retrieval functions
- `dt`, `date` - unused in pattern matches

### Common Unused Aliases
- `Instruction` - in `lib/jump/agent.ex`, `lib/jump/agent/context.ex`, `lib/jump/rag/answer_builder.ex`
- `Tasks` - in `lib/jump/agent/context.ex`
- `Agent`, `Messaging` - in `lib/jump/agent/tasks.ex`
- `Message` - in `lib/jump/agent/tools.ex`, `lib/jump/rag/tools.ex`, `lib/jump/agent.ex`
- `Repo` - in `lib/jump/agent.ex`
- `Retriever` - in `lib/jump/rag/answer_builder.ex`
- `Chunk` - in `lib/jump/rag/retriever.ex`

### Fix Strategy
Prefix unused variables with `_` (e.g., `_timezone`, `_query_text`) or remove unused aliases.

---

## 11. Type Violations and Never-Matching Clauses

### Issue
Pattern matches that will never execute due to type analysis.

### Errors
- `{:error, _}` clauses will never match because function always returns `{:ok, term()}`
  - **Files**:
    - `lib/jump/rag/retriever.ex:90, 110, 326, 598`
    - `lib/jump/rag/tools.ex:343, 599`
    - `lib/jump/rag/search.ex:92, 352, 366, 381, 409`

- `{:error, reason}` won't match in calendar sync
  - **Files**: `lib/jump/workers/calendar_sync.ex:62`

### Fix Strategy
Remove unreachable error clauses or update functions to actually return errors.

---

## 12. Missing Required Parameters

### Issue
Functions being called with insufficient parameters.

### Errors
- `DateTime.from_iso8601!/1` called instead of `/2` or `/3`
  - The bang version expects a string and returns a datetime, but `/2` handles timezone
  - **Fix**: Use the version appropriate for your use case

---

## Summary Statistics

- **Total Warning Categories**: 12
- **Most Common Issues**: 
  1. Google API method signatures (20+ instances)
  2. DateTime/Date module functions (25+ instances)
  3. Unused variables and aliases (50+ instances)
  4. Type mismatches (10+ instances)
  5. Deprecated Logger methods (10+ instances)

---

## Fix Status

### ✅ COMPLETED
- **Google Calendar API method signatures** - ALL FIXED
  - Fixed `lib/jump/calendar/client.ex`: 8 function calls corrected
  - Fixed `lib/jump/calendar/events.ex`: 1 function call corrected
  - All calls now use correct module functions with `calendar_` prefix
  - All required parameters now in place

- **Google Gmail API method signatures** - ALL FIXED
  - Fixed `lib/jump/gmail/client.ex`: 8 function calls corrected
  - All calls now pass user_id ("me") and message_id/thread_id as explicit parameters
  - Fixed functions: messages_list, messages_get, messages_send, messages_modify, history_list, watch, stop, threads_get

### 🔄 IN PROGRESS / TODO
- DateTime/Date module functions (25+ errors)
- Swoosh Email API methods (3 errors)
- Missing module implementations (6 errors)
- Type mismatches and unused variables

## Recommended Fix Priority

1. **High Priority** (breaks functionality):
   - ✅ ~~Google API method signatures~~ COMPLETED
   - DateTime/Date module functions (many errors)
   - Gmail API method signatures
   - Missing module implementations
   - Type mismatches

2. **Medium Priority** (compilation warnings):
   - Swoosh Email API
   - Missing required parameters

3. **Low Priority** (code quality):
   - Unused variables
   - Unused aliases
   - Deprecated functions
