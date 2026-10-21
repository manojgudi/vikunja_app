Name:       harbour-vikunja
Summary:    Vikunja client for Sailfish OS
Version:    0.2.9
Release:    1
License:    MIT
URL:        https://github.com/manojgudi/vikunja_app
Source0:    %{name}-%{version}.tar.bz2
Requires:   sailfishsilica-qt5 >= 0.10.9
Requires:   nemo-qml-plugin-notifications-qt5
BuildRequires:  pkgconfig(sailfishapp) >= 1.0.2
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  desktop-file-utils

%description
Manage the projects, tasks, kanban boards, labels and comments of a
self-hosted Vikunja server. Credentials are kept in Sailfish Secrets and
the app runs inside the sailjail sandbox.

%prep
%setup -q -n %{name}-%{version}

%build
%qmake5
%make_build

%install
%qmake5_install

desktop-file-install --delete-original \
  --dir %{buildroot}%{_datadir}/applications \
   %{buildroot}%{_datadir}/applications/*.desktop

%files
%defattr(-,root,root,-)
%{_bindir}/%{name}
%{_datadir}/%{name}
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/*/apps/%{name}.png
%{_datadir}/lipstick/notificationcategories/x-harbour-vikunja.reminder.conf

%changelog
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.9-1
- Tapping a reminder opens the task again (and "Mark done" works): lipstick
  sends the task id as a double, which the app refused as an unknown method,
  so the app started hidden and never showed a window.

* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.8-1
- Diagnostics for opening a task from a reminder: the session log now
  records the D-Bus name, each incoming call, window changes, how the app
  exits, crash signals with a backtrace, and Qt/QML warnings (redacted).

* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.7-1
- Opening from a reminder keeps you signed in: Secrets treats a reminder
  start and a launcher start as different apps, so the token is now split
  into a random pad in the app's private folder and token XOR pad in a
  Secrets collection both starts can read. Existing sign-ins are moved.
- Reminders play a short alert tone (vibration when silent) and show a
  banner.
- Cover counts open tasks still due later today, plus overdue ones, and
  refreshes every minute.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.6-1
- Session diagnostics log (~/.cache/io.github.manojgudi/harbour-vikunja/session.log,
  no tokens or task data) to trace starts from reminders.
- Set XDG_RUNTIME_DIR when D-Bus activation leaves it out, so Sailfish
  Secrets can be reached from a reminder start.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.5-1
- Opening the app from a reminder no longer shows the login page: the
  session is restored before QML and D-Bus calls run, and the login page
  moves on to the home page if a session appears while it is showing.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.4-1
- Fix being signed out whenever the app closed: settings were written next
  to the folder sailjail keeps, so inside the sandbox they were lost on exit.
  They now live in ~/.config/io.github.manojgudi/harbour-vikunja/.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.3-1
- Never block startup on Sailfish Secrets: it is contacted after the window
  is up, every request gives up after 4 seconds, and the old 0.2.0 token
  clean-up runs only once.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.2-1
- If Sailfish Secrets refuses the token, ask before keeping it in the
  private-folder file; the choice can be changed in Settings.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.1-1
- Stay signed in after closing the app: the launcher no longer starts the app
  through a shared booster, every save to Sailfish Secrets is read back, and
  if Secrets refuses it the token goes to a private 0600 file instead.
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.0-1
- Reminders are scheduled with timed and arrive while the app is closed.
- Projects open as a kanban board; the list is one pull-down away.
- One date and time dialog; due-date presets stay editable.
- Light, dark or ambience theme.

* Tue Oct 20 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.1.0-1
- First Sailfish OS release: projects, tasks, kanban, labels, comments,
  attachments, reminders, cover; Sailfish Secrets token storage, TLS pinning.
