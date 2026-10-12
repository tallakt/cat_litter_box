defmodule CatLitterBox do
  @moduledoc """
  Logs the cat's weight from a Tuya litter box to Arrow files in `log/`, and tells on ntfy which of
  the cats it was. Tuya pushes each report over a WebSocket, which is connected again when it drops.

      iex --sname cat -S mix

  The Tuya cloud project's keys come from the environment, `TUYA_ACCESS_ID` and
  `TUYA_ACCESS_SECRET`.

  ## The supervision tree

  ```
  CatLitterBox.Supervisor          rest_for_one
  ├─ CatLitterBox.TuyaStore        the :tuya partition the socket writes, with its points declared
  ├─ CatLitterBox.Plant            the program: the :cat_logger store, the historian and the runner
  └─ CatLitterBox.Tuya             the WebSocket to Tuya
  ```

  A socket that stops is started again by itself, and the program logs on meanwhile. The program
  reads the weight with its quality: until the socket has read it after a start, it is not good, so
  the historian holds it back and the notifications pass it over.

  ## Setting up Tuya

  Tuya pushes nothing until all of this is done on https://platform.tuya.com. Without any one step
  the socket connects and Tuya answers its pings, but no report ever comes, and nothing says why:

    1. Cloud → Development → Create Cloud Project, in the data centre of the app account: Central
       Europe here, which is the host mqe.tuyaeu.com in `CatLitterBox.Tuya`. Its Overview has the
       Access ID and the Access Secret, which go in `TUYA_ACCESS_ID` and `TUYA_ACCESS_SECRET` in the
       environment.
    2. Devices → Link App Account → Add App Account, and scan the QR code in the Tuya or Smart Life
       app of the account that owns the litter box. A device only shared with the linked account
       reads fine over REST but is never pushed: the owner's account must be the one linked.
    3. Message Service: turn it on, as a Message Queue.
    4. Message Service → Messaging Rules → Production Environment → Create Messaging Rules: Add
       Message Filtering Rule, BizCode (Message Type) In devicePropertyMessage and
       deviceEventMessage, then Release Rule and OK.
    5. Then turn on the switch beside "The rules for the production environment are disabled": a
       released rule pushes nothing until it is on. The page then says the rules are in effect.

  To test it, change a setting of the litter box in the app: the log prints a "report:" line within
  seconds. The device's id, in `CatLitterBox.Tuya`, is from the project's Devices list.
  """
end
