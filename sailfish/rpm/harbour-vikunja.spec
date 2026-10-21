Name:       harbour-vikunja
Summary:    Vikunja client for Sailfish OS
Version:    0.2.0
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

%changelog
* Wed Oct 21 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.2.0-1
- Reminders are scheduled with timed and arrive while the app is closed.
- Projects open as a kanban board; the list is one pull-down away.
- One date and time dialog; due-date presets stay editable.
- Light, dark or ambience theme.

* Tue Oct 20 2026 Vikunja Sailfish port <noreply@anthropic.com> - 0.1.0-1
- First Sailfish OS release: projects, tasks, kanban, labels, comments,
  attachments, reminders, cover; Sailfish Secrets token storage, TLS pinning.
