// These pin the Firm/Personal rules to the web app's behaviour. The mobile
// classification and the visibility condition for the switch are ports of
// src/lib/org-helpers.ts and src/components/layout/OrgSelector.tsx; if either
// side drifts, an accountant sees a different set of workspaces on the phone
// than at the desk, which is exactly the kind of bug nobody notices until a
// client's books show up under the wrong heading.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/workspace_service.dart';
import 'package:ledgiproof/widgets/capture_sheet.dart';

Workspace ws(String name, OrgCategory cat, {String role = 'owner'}) => Workspace(
      orgId: name,
      orgName: name,
      role: role,
      isFirm: cat == OrgCategory.firm,
      category: cat,
    );

WorkspaceScope scopeOf(List<Workspace> orgs,
        {required bool eligible, Workspace? active}) =>
    WorkspaceScope(
      orgs: orgs,
      active: active ?? orgs.first,
      isToggleEligibleRole: eligible,
    );

void main() {
  group('classify', () {
    test('explicit flags win over the account_type fallback', () {
      expect(
        WorkspaceService.classify({'is_personal': true}, 'bookkeeper'),
        OrgCategory.personal,
      );
      expect(
        WorkspaceService.classify({'is_firm': true}, 'self_employed'),
        OrgCategory.firm,
      );
      expect(
        WorkspaceService.classify({'is_client': true}, 'bookkeeper'),
        OrgCategory.clientCompany,
      );
    });

    test('falls back to account_type when no flag is set', () {
      expect(WorkspaceService.classify({}, 'self_employed'),
          OrgCategory.personal);
      expect(WorkspaceService.classify({}, 'bookkeeper'), OrgCategory.firm);
      expect(WorkspaceService.classify({}, 'pyme_client'),
          OrgCategory.clientCompany);
    });

    test('unknown when there is neither a flag nor a usable hint', () {
      expect(WorkspaceService.classify({}, null), OrgCategory.unknown);
      expect(WorkspaceService.classify({}, 'accountant'), OrgCategory.unknown);
    });

    test('false flags are not treated as true', () {
      expect(
        WorkspaceService.classify(
            {'is_personal': false, 'is_firm': false, 'is_client': false}, null),
        OrgCategory.unknown,
      );
    });
  });

  group('when the Firm/Personal switch is offered', () {
    test('shown for an eligible role that owns a firm', () {
      final s = scopeOf([ws('Firm', OrgCategory.firm)], eligible: true);
      expect(s.canToggle, isTrue);
    });

    test('hidden for an eligible role with no firm workspace', () {
      // A solo user whose role happens to be eligible still has nothing to
      // switch between.
      final s = scopeOf([ws('Mine', OrgCategory.personal)], eligible: true);
      expect(s.canToggle, isFalse);
    });

    test('hidden for an ineligible role even when a firm is present', () {
      // A client-portal user or an auditor inside a firm must never see it.
      final s = scopeOf([ws('Firm', OrgCategory.firm)], eligible: false);
      expect(s.canToggle, isFalse);
    });

    test('still shown when the personal workspace does not exist yet', () {
      // The Personal side becomes a create action rather than disappearing.
      final s = scopeOf([ws('Firm', OrgCategory.firm)], eligible: true);
      expect(s.canToggle, isTrue);
      expect(s.hasPersonal, isFalse);
    });
  });

  group('partitioning', () {
    final orgs = [
      ws('Firm A', OrgCategory.firm),
      ws('Firm B', OrgCategory.firm),
      ws('Mine', OrgCategory.personal),
      ws('Client Co', OrgCategory.clientCompany),
      ws('Mystery', OrgCategory.unknown),
    ];

    test('each workspace lands in exactly one bucket', () {
      final s = scopeOf(orgs, eligible: true);
      expect(s.firmOrgs.length, 2);
      expect(s.personalOrgs.length, 1);
      expect(s.clientOrgs.length, 1);
      expect(
        s.firmOrgs.length + s.personalOrgs.length + s.clientOrgs.length,
        orgs.length - 1, // the unknown one belongs to no bucket
      );
    });

    test('hasPersonal reflects the personal bucket', () {
      expect(scopeOf(orgs, eligible: true).hasPersonal, isTrue);
      expect(
        scopeOf([ws('Firm', OrgCategory.firm)], eligible: true).hasPersonal,
        isFalse,
      );
    });
  });

  group('what Capture offers per workspace', () {
    // Mileage and bank connections are deductions against one set of books, and
    // a firm workspace is not one. These guard the rule at the only place it is
    // written, since both the Capture sheet and the Home quick actions read it.
    test('firm mode drops mileage and keeps everything else', () {
      final actions = captureActionsFor(ws('Firm', OrgCategory.firm));
      expect(actions.map((a) => a.label), isNot(contains('Log a trip')));
      expect(actions.map((a) => a.label),
          containsAll(['Scan receipt', 'Log time', 'Manual expense']));
    });

    test('personal and client workspaces keep mileage', () {
      for (final cat in [
        OrgCategory.personal,
        OrgCategory.clientCompany,
        OrgCategory.unknown
      ]) {
        expect(
          captureActionsFor(ws('W', cat)).map((a) => a.label),
          contains('Log a trip'),
          reason: 'mileage should stay available in $cat',
        );
      }
    });
  });

  group('remembering which workspace you were in', () {
    // A staff membership is identified by its org. A client-of-a-firm is NOT:
    // one profile can hold several portal memberships, and two of them can sit
    // under the SAME firm org. The portal loader matches the remembered value
    // against the MEMBERSHIP id, so that is what has to be stored -- storing
    // the org id meant nothing ever matched and a client with more than one
    // business was silently dropped back to the first on every launch.
    test('a staff workspace remembers its org id', () {
      final w = ws('Firm', OrgCategory.firm);
      expect(w.rememberKey, w.orgId);
    });

    test('a portal workspace remembers its membership id, not the org', () {
      final w = Workspace(
        orgId: 'firm-org',
        orgName: 'Acme',
        role: 'client_owner',
        isFirm: false,
        category: OrgCategory.clientCompany,
        isPortalClient: true,
        portalClientId: 'client-1',
        portalMembershipId: 'membership-1',
      );
      expect(w.rememberKey, 'membership-1');
      expect(w.rememberKey, isNot(w.orgId));
    });

    test('two portal memberships under one firm stay distinguishable', () {
      Workspace m(String id, String client) => Workspace(
            orgId: 'same-firm',
            orgName: client,
            role: 'client_owner',
            isFirm: false,
            category: OrgCategory.clientCompany,
            isPortalClient: true,
            portalClientId: client,
            portalMembershipId: id,
          );
      expect(m('a', 'c1').rememberKey, isNot(m('b', 'c2').rememberKey));
    });
  });
}
