# use Mix.Config
# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of the Config module.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
import Config

config :data_manager, DataManager.Repo,
  database: "data_manager_repo",
  username: "postgres",
  password: "postpassword",
  hostname: "localhost",
  port: 5432,
  log: false

config :data_manager, ecto_repos: [DataManager.Repo]

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

if Mix.env() != :prod do
  config :git_hooks,
    auto_install: true,
    verbose: true,
    hooks: [
      pre_commit: [
        tasks: [
          {:cmd, "mix format"}
        ]
      ],
      pre_push: [
        verbose: false,
        tasks: [
          # {:cmd, "mix dialyzer"},
          {:cmd, "mix test"},
          {:cmd, "echo 'success!'"}
        ]
      ]
    ]
end
