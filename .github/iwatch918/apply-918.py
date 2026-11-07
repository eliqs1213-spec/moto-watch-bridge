#!/usr/bin/env python3
"""918: trace picker presentation and retry only after foreground activation."""
from pathlib import Path
p=Path("ios-native/project.yml")
s=p.read_text()
assert s.count("CFBundleVersion: '916'")==2
s=s.replace("CFBundleVersion: '916'","CFBundleVersion: '918'").replace("CFBundleShortVersionString: '0.8.4.72'","CFBundleShortVersionString: '0.8.4.73'")
p.write_text(s)
p=Path("ios-native/Sources/MotoAccessorySetupCoordinator.swift")
s=p.read_text()
needle='''        // La presentación sigue respondiendo al botón que pulsó el usuario;'''
assert s.count(needle)==1
s=s.replace(needle,'''        log("918: becameActive; sesión activa, intentando presentar selector")
'''+needle)
needle='''        pickerAttemptedThisLaunch = true
        let descriptor = ASDiscoveryDescriptor()'''
assert s.count(needle)==1
s=s.replace(needle,'''        pickerAttemptedThisLaunch = true
        log("918: showPicker solicitado; appState=\\(UIApplication.shared.applicationState.rawValue)")
        let descriptor = ASDiscoveryDescriptor()''')
needle='''        session.showPicker(for: [entry]) { [weak self] error in
            guard let self, let error else { return }'''
assert s.count(needle)==1
s=s.replace(needle,'''        session.showPicker(for: [entry]) { [weak self] error in
            guard let self else { return }
            guard let error else {
                self.log("918: showPicker completion sin error; esperando evento de iOS")
                return
            }''')
needle='''        switch event.eventType
'''
# Log every callback regardless of event
needle='''        switch event.eventType {'''
assert s.count(needle)==1
s=s.replace(needle,'''        log("918: evento AccessorySetupKit=\\(event.eventType)")
        switch event.eventType {''')
# The foreground event may happen before session activation; defer one safe attempt
needle='''            if !isAuthorized { becameActive() }'''
assert s.count(needle)==1
s=s.replace(needle,'''            if !isAuthorized {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.becameActive()
                }
            }''')
p.write_text(s)
print("918: instrumented AccessorySetupKit picker, events, and foreground retry")
