/// Role-based capability matrix. Mirrors the server (`backend/src/auth.js`), which is the
/// authority; the client uses it only to hide actions the server would reject.
class Perm {
  Perm._();
  static const membersRead = 'members.read';
  static const membersWrite = 'members.write';
  static const plansRead = 'plans.read';
  static const plansWrite = 'plans.write';
  static const financeRead = 'finance.read';
  static const financeWrite = 'finance.write';
  static const leadsRead = 'leads.read';
  static const leadsWrite = 'leads.write';
  static const attendanceRead = 'attendance.read';
  static const attendanceWrite = 'attendance.write';
  static const productsRead = 'products.read';
  static const productsWrite = 'products.write';
  static const expensesRead = 'expenses.read';
  static const expensesWrite = 'expenses.write';
  static const broadcastsRead = 'broadcasts.read';
  static const broadcastsWrite = 'broadcasts.write';
  static const plansetsRead = 'plansets.read';
  static const plansetsWrite = 'plansets.write';
  static const staffRead = 'staff.read';
  static const staffWrite = 'staff.write';
  static const devicesRead = 'devices.read';
  static const devicesWrite = 'devices.write';
  static const reportsRead = 'reports.read';
  static const settingsRead = 'settings.read';
  static const settingsWrite = 'settings.write';
  static const feedbackRead = 'feedback.read';
  static const videosWrite = 'videos.write';
  static const trainersWrite = 'trainers.write';
  static const trainerSelf = 'trainer.self';
}

const _matrix = <String, Set<String>>{
  'owner': {'*'},
  'manager': {
    Perm.membersRead,
    Perm.membersWrite,
    Perm.plansRead,
    Perm.plansWrite,
    Perm.financeRead,
    Perm.financeWrite,
    Perm.leadsRead,
    Perm.leadsWrite,
    Perm.attendanceWrite,
    Perm.attendanceRead,
    Perm.productsRead,
    Perm.productsWrite,
    Perm.expensesRead,
    Perm.expensesWrite,
    Perm.broadcastsRead,
    Perm.broadcastsWrite,
    Perm.plansetsRead,
    Perm.plansetsWrite,
    Perm.staffRead,
    Perm.devicesRead,
    Perm.devicesWrite,
    Perm.reportsRead,
    Perm.settingsRead,
    Perm.feedbackRead,
    Perm.videosWrite,
    Perm.trainersWrite,
    Perm.settingsWrite,
  },
  'staff': {
    Perm.membersRead,
    Perm.membersWrite,
    Perm.plansRead,
    Perm.financeRead,
    Perm.financeWrite,
    Perm.leadsRead,
    Perm.leadsWrite,
    Perm.attendanceWrite,
    Perm.attendanceRead,
    Perm.productsRead,
    Perm.productsWrite,
    Perm.plansetsRead,
    Perm.reportsRead,
    Perm.settingsRead,
    Perm.feedbackRead,
  },
  'trainer': {
    Perm.membersRead,
    Perm.attendanceRead,
    Perm.plansRead,
    Perm.plansetsRead,
    Perm.plansetsWrite,
    Perm.trainerSelf,
  },
};

bool roleCan(String? role, String perm) {
  final p = _matrix[role];
  return p != null && (p.contains('*') || p.contains(perm));
}

String roleLabel(String role) => switch (role) {
  'owner' => 'Owner',
  'manager' => 'Manager',
  'staff' => 'Staff',
  'trainer' => 'Trainer',
  _ => role,
};
