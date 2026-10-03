# smokenot

A small offline companion for leaving the cigarette behind, written in Mojo
with GTK 4. It counts the days, the money and the cigarettes you did not smoke,
puts a five minute breathing session next to you when a craving shows up, and
keeps a short journal of cravings and slips so you can see your own pattern
instead of guessing at it.

Everything lives in one file in your own home directory. There is no account,
no network use and no telemetry: the app never opens a socket, and it works
with the machine offline.

The counters are a way to notice your own progress. They are not medical advice
and they are not a diagnosis of anything. If quitting is hard on you, talking
to a doctor or a stop smoking service is a better use of your time than any
number on a screen.

## What is in the box

The interface is in Portuguese or English, chosen in the settings, and both
languages live in the program: nothing is fetched and nothing is translated at
run time.

- **The settings page sets everything up**, and it is the only place any of it
  is written. On the first run the app opens straight onto it, with no tabs: how
  many cigarettes a day you smoke, how many come in a pack, what a pack costs,
  and the day you mean to stop, picked from a month grid. Save and the
  dashboard is there, tabs and all. Later, the same page holds the values you
  already have, so a change is an edit rather than a fresh start.
- **The day can be today or any day to come.** Pick today and the count starts
  the moment you save, not at midnight, because a person picking today means
  "from now". Pick a day that has not arrived yet and the dashboard counts down
  to it instead, and the date it will count from is written on the page. On the
  day itself the dashboard waits with a **Quit now!** button, so the day is what
  you chose and the hour is the one you press.
- **The dashboard** shows the days since the last cigarette, the money not
  spent, the cigarettes not smoked, the next milestone and a bar that fills up
  as the next one comes closer.
- **A craving session** is a five minute breathing exercise with a moving
  circle. Start it when the urge shows up, and it can be stopped or left to
  finish.
- **The journal** is where cravings and slips are written down, one tap each
  with a note if you want one. A slip is not a failure to be punished: it is
  counted, and the app keeps counting from where you are.
- **The settings** also hold the language, the path of the saved file, a short
  explanation of what the numbers mean and a reset that asks twice. The reset
  takes you back to a blank setup page rather than an empty dashboard.

## Building it

You need the Mojo compiler and the GTK 4 development files.

```sh
python3 -m venv .venv
.venv/bin/pip install mojo_compiler==1.1.0 mojo_compiler_mojo_libs==1.1.0
```

`build.sh` wraps the rest:

```sh
./build.sh test     # the logic tests
./build.sh probe    # the window, driven without a person in front of it
./build.sh app      # build/smokenot
./build.sh check    # test, probe, then the app
./build.sh all      # the same as check
./build.sh clean
```

The app calls GTK, cairo and glib directly, so the build passes the link flags
for them explicitly:

```sh
.venv/bin/mojo build src/main.mojo -o build/smokenot \
  -Xlinker=-lgtk-4 -Xlinker=-lcairo -Xlinker=-lgobject-2.0 \
  -Xlinker=-lgio-2.0 -Xlinker=-lglib-2.0
```

Then run `./build/smokenot`.

## How the code is laid out

```
snapcraft.yaml      the strict core24 snap
snap/
  stage.sh          the build the snap part runs
  assets/           the desktop file, the icon and the AppStream metadata
src/
  main.mojo          the entry point
  ui/app.mojo        starting GTK and waiting on the main loop
  lib/sys.mojo       the clock, the files and the local calendar day
  ui/screens.mojo    building the window and rewriting its text
  ui/handlers.mojo   the GTK callbacks and how they are connected
  ui/host.mojo       where the saved state lives while the window is open
  ui_probe.mojo      the window, driven end to end without a person
  gtk/gtk.mojo       the GTK 4 and cairo calls, typed and named
  model/             the profile, the statistics and the milestones
  i18n/strings.mojo  the Portuguese and English text
  lib/               the clock, the files, and the small text helpers
  selftest.mojo      the logic test runner
  tests/             the tests themselves
  gtk_smoke.mojo     a small GTK program that proves the bindings work
```

Two things about Mojo shape the whole thing. There are no globals, so the
saved state is parked in memory the callbacks can reach and passed to them by
address. And a function cannot travel as an ordinary argument, so every place
that hands a callback to GTK names the callback in the call instead of putting
it in a variable.

## The snap

`snapcraft.yaml` at the top of the repository describes a strict `core24` snap.
It lives there on purpose: a managed build pushes the project directory into
the builder, and the sources, the script and the assets all have to travel with
it.

The build happens inside core24 because the compiler is a native binary and one
built against a newer glibc would not start there. `snap/stage.sh` installs the
compiler into a throwaway environment, builds the app, and lays out the binary,
the compiler's own runtime libraries, the desktop file, the icon and the
AppStream metadata. The binary is given a run path of `$ORIGIN/../lib` so it
finds those libraries inside the snap, where nothing is installed on the
system. GTK, the themes and the fonts come from the `gnome` extension, which is
the usual way to get a GTK application looking like itself in a strict snap.

The app asks for no name on the session bus: it is a plain window on a main
loop of its own, so there is nothing there for the confinement to refuse, and
it needs no `dbus` plug.

```sh
./build.sh snap                      # or: snapcraft pack
sudo snap install --dangerous smokenot_0.1.0_amd64.snap
```

The build takes a couple of minutes, most of it spent pushing the project
directory into the builder.

The saved file lives under `$SNAP_USER_DATA`, which is inside
`~/snap/smokenot/current/.local/share` and is not a symlink, so nothing outside
the app can be read by accident and nothing in the snap can be changed from
outside either.

## Where the data goes

One file: `$XDG_DATA_HOME/smokenot/state.json`, which is
`~/.local/share/smokenot/state.json` normally, and inside
`~/snap/smokenot/current/.local/share/smokenot/state.json` in the snap. It
holds the three habit numbers, the day the count runs from, the language, the
list of journal entries, whether the setup has been filled in, and whether the
count has actually started, so the app knows to open on the settings page
instead of the dashboard and to tell a plan from a count that is under way.

The settings screen shows that path, and the reset button deletes the file.

## Licence

GPL-3.0-or-later, as declared in `snap/snapcraft.yaml`. A `LICENSE` file should
be added before this goes anywhere but this machine.
