# billing-scripts for integration with payment system

The scripts in billing system to provide the integration with OPLATA.RU payment system.
* `oplata.pl` – processes the request from the payment system with three possible actions:
  - ‘check’ – checks if user exist in billing DB.
  - ‘payment’ – processes the payment transaction with balance of the user. Executes `oplata_client.pl` script.
  - ‘status’ – gets the status of current payment.
* `oplata_client.pl` – gets the balance (state of it) for current user and executes `ban_user.pl` script.
* `ban_user.pl` – bans or unbans the current user according to balance (if balance <= 0 – ban, else – unban).
