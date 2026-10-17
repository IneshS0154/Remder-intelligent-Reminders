import SwiftData
import SwiftUI

struct SidebarView: View {
    @Bindable var navigation: AppNavigation
    let close: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ReminderCategory.sortOrder), SortDescriptor(\ReminderCategory.createdDate)])
    private var categories: [ReminderCategory]
    @Query(filter: #Predicate<Reminder> { !$0.isCompleted }) private var activeReminders: [Reminder]
    @Query private var notes: [Note]

    @State private var editingCategory: ReminderCategory?
    @State private var creatingCategory = false
    @State private var deletingCategory: ReminderCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row(title: "All Reminders", icon: "tray.full", tint: .accentColor,
                        count: activeReminders.count,
                        isSelected: navigation.section == .reminders && navigation.selectedCategory == nil) {
                        select(.reminders, category: nil)
                    }

                    row(title: "Notes", icon: AppSection.notes.icon, tint: .orange,
                        count: notes.count, isSelected: navigation.section == .notes) {
                        select(.notes, category: navigation.selectedCategory)
                    }

                    row(title: "Insights", icon: AppSection.insights.icon, tint: .red,
                        count: nil, isSelected: navigation.section == .insights) {
                        select(.insights, category: navigation.selectedCategory)
                    }

                    sectionHeader("Categories") { EmptyView() }

                    ForEach(categories) { category in
                        row(title: category.name, icon: "circle.fill", tint: category.color.color,
                            count: activeReminders.filter { $0.category == category.name }.count,
                            isSelected: navigation.section == .reminders && navigation.selectedCategory == category.name) {
                            select(.reminders, category: category.name)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingCategory = category }
                            Button("Delete", systemImage: "trash", role: .destructive) { deletingCategory = category }
                        }
                    }

                    row(title: "Add Category", icon: "plus", tint: .accentColor, count: nil, isSelected: false) {
                        creatingCategory = true
                    }

                    sectionHeader("App") { EmptyView() }

                    ForEach([AppSection.settings, .about]) { section in
                        row(title: section.title, icon: section.icon, tint: .secondary, count: nil,
                            isSelected: navigation.section == section) {
                            select(section, category: navigation.selectedCategory)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .sheet(isPresented: $creatingCategory) {
            CategoryEditorView(category: nil)
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category)
        }
        .confirmationDialog(
            "Delete \"\(deletingCategory?.name ?? "")\"?",
            isPresented: Binding(get: { deletingCategory != nil }, set: { if !$0 { deletingCategory = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) {
                guard let category = deletingCategory else { return }
                if navigation.selectedCategory == category.name { navigation.selectedCategory = nil }
                CategoryStore.delete(category, in: modelContext)
            }
        } message: {
            Text("Its reminders are kept and moved to No Category.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text("Remder")
                .font(.title2.bold())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private func row(title: String, icon: String, tint: Color, count: Int?, isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(icon == "circle.fill" ? .system(size: 11) : .body)
                    .foregroundStyle(isSelected ? Color.accentColor : tint)
                    .frame(width: 24)
                Text(title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ section: AppSection, category: String?) {
        navigation.section = section
        navigation.selectedCategory = category
        close()
    }
}

/// Create or edit a category: name and color.
struct CategoryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [ReminderCategory]

    let category: ReminderCategory?
    /// Called with the saved category's name (used by the reminder form to select it).
    var onSave: ((String) -> Void)? = nil

    @State private var name: String
    @State private var color: CategoryColor

    init(category: ReminderCategory?, onSave: ((String) -> Void)? = nil) {
        self.category = category
        self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
        _color = State(initialValue: category?.color ?? .blue)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDuplicate: Bool {
        categories.contains { $0 !== category && $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 14, height: 14)
                        TextField("Category name", text: $name)
                            .font(.body.weight(.medium))
                    }
                } footer: {
                    if isDuplicate {
                        Text("A category with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 14) {
                        ForEach(CategoryColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if option == color {
                                            Circle().strokeBorder(.background, lineWidth: 3)
                                            Circle().strokeBorder(option.color, lineWidth: 2).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.rawValue.capitalized)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || isDuplicate)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let category {
            category.color = color
            CategoryStore.rename(category, to: trimmedName, in: modelContext)
        } else {
            let nextOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
            modelContext.insert(ReminderCategory(name: trimmedName, color: color, sortOrder: nextOrder))
        }
        try? modelContext.save()
        onSave?(trimmedName)
        dismiss()
    }
}
