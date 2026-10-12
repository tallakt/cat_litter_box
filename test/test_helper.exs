# The tests don't start the application, which would connect to Tuya (mix.exs runs `mix test` with
# --no-start); only xignal is started.
{:ok, _apps} = Application.ensure_all_started(:xignal)
ExUnit.start()
