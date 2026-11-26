import UIKit

final class GroupMemberPickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let manager: ImService
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let selectedLabel = UILabel()
    private var candidates: [WatchImGroupCandidate] = []
    private var selected: [String: WatchImGroupCandidate] = [:]
    private var defaultSelectedUserIDs = Set<String>()

    var onBack: (() -> Void)?
    var onDone: (([WatchImGroupCandidate]) -> Void)?

    init(manager: ImService) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDefaultSelectedUserIDs(_ userIDs: Set<String>) {
        defaultSelectedUserIDs = Set(userIDs.filter { !$0.isEmpty })
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WatchTheme.background
        buildView()
        selectedLabel.text = String(format: NSLocalizedString("watch_group_member_picker_selected", comment: ""), 0)
        manager.loadGroupCandidates { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                let loaded = (try? result.get()) ?? []
                let knownIDs = Set(loaded.map(\.userID))
                let currentUserID = self.manager.loggedInUserID ?? ""
                let missing = self.defaultSelectedUserIDs.filter { !knownIDs.contains($0) }.map { userID in
                    WatchImGroupCandidate(
                        userID: userID,
                        displayName: userID,
                        avatarKey: WatchAvatarResolver.key(for: userID),
                        isWatch: userID != currentUserID,
                        isCurrentUser: userID == currentUserID
                    )
                }
                self.candidates = (loaded + missing).reduce(into: [String: WatchImGroupCandidate]()) { $0[$1.userID] = $0[$1.userID] ?? $1 }.map(\.value)
                self.selected = self.candidates.filter { self.defaultSelectedUserIDs.contains($0.userID) }.reduce(into: [String: WatchImGroupCandidate]()) { $0[$1.userID] = $1 }
                self.tableView.reloadData()
                self.selectedLabel.text = String(format: NSLocalizedString("watch_group_member_picker_selected", comment: ""), self.selected.count)
            }
        }
    }

    private func buildView() {
        let header = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = WatchTheme.backButton(
            identifier: "group.back",
            label: NSLocalizedString("watch_chat_back", comment: "")
        ) { [weak self] in
            self?.onBack?()
        }
        header.addSubview(back)
        let title = WatchTheme.label("watch_group_member_picker_title", size: 19, weight: .bold)
        title.textAlignment = .center
        header.addSubview(title)
        let done = UIButton(type: .system)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.setTitle(NSLocalizedString("watch_group_member_picker_done", comment: ""), for: .normal)
        done.setTitleColor(WatchTheme.blue, for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        header.addSubview(done)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8), header.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor), back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 48), title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -48), title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: header.trailingAnchor), done.centerYAnchor.constraint(equalTo: header.centerYAnchor), done.widthAnchor.constraint(equalToConstant: 56), done.heightAnchor.constraint(equalToConstant: 40),
            
        ])

        selectedLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedLabel.font = .systemFont(ofSize: 13)
        selectedLabel.textColor = WatchTheme.secondaryText
        view.addSubview(selectedLabel)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = WatchTheme.surface
        tableView.layer.cornerRadius = 18
        tableView.separatorColor = WatchTheme.line
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(GroupMemberPickerCell.self, forCellReuseIdentifier: "GroupMemberCell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            selectedLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), selectedLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), selectedLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4), selectedLabel.heightAnchor.constraint(equalToConstant: 36),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20), tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20), tableView.topAnchor.constraint(equalTo: selectedLabel.bottomAnchor), tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func submit() {
        guard !selected.isEmpty else {
            let alert = UIAlertController(title: nil, message: NSLocalizedString("watch_group_member_picker_empty", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("watch_common_ok", comment: ""), style: .default))
            present(alert, animated: true)
            return
        }
        onDone?(Array(selected.values))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { candidates.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "GroupMemberCell", for: indexPath) as! GroupMemberPickerCell
        let candidate = candidates[indexPath.row]
        cell.configure(candidate, selected: selected[candidate.userID] != nil)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let candidate = candidates[indexPath.row]
        if selected[candidate.userID] == nil { selected[candidate.userID] = candidate } else { selected.removeValue(forKey: candidate.userID) }
        tableView.reloadRows(at: [indexPath], with: .none)
        selectedLabel.text = String(format: NSLocalizedString("watch_group_member_picker_selected", comment: ""), selected.count)
    }
}

private final class GroupMemberPickerCell: UITableViewCell {
    private let nameLabel = UILabel()
    private let checkIcon = WatchTheme.icon(.check, tint: WatchTheme.blue, size: 22)
    private var avatarView: UIView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 15)
        nameLabel.textColor = WatchTheme.primaryText
        contentView.addSubview(nameLabel)
        contentView.addSubview(checkIcon)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 68),
            nameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: checkIcon.leadingAnchor, constant: -12),
            checkIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            checkIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ candidate: WatchImGroupCandidate, selected: Bool) {
        nameLabel.text = candidate.displayName
        checkIcon.isHidden = !selected
        avatarView?.removeFromSuperview()
        let avatar = WatchTheme.avatar(textKey: candidate.avatarKey, color: WatchTheme.mint.withAlphaComponent(0.2), size: 40)
        contentView.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        avatarView = avatar
    }
}
