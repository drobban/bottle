# DataManager

mix ecto.create

mix ecto.gen.migration xxxx_xxxx - to create new migration template

mix ecto.migrate

**To clear db**

dropdb -U postgres data_manager_repo -h 127.0.0.1 -p 5432
