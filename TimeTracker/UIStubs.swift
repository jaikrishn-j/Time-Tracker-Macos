import SwiftUI
import SwiftData

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack {
            Text(project.name)
                .font(.headline)
            Spacer()
            Text("\(project.subtasks.count) subtasks")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ProjectDetailView: View {
    let project: Project

    var body: some View {
        List {
            ForEach(project.subtasks) { subtask in
                Text(subtask.title)
            }
        }
        .navigationTitle(project.name)
    }
}

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var projectDescription: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project Name", text: $name)
                }
                Section("Description") {
                    TextField("Description (optional)", text: $projectDescription)
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let newProject = Project(name: name)
                        if !projectDescription.isEmpty {
                            newProject.projectDescription = projectDescription
                        }
                        modelContext.insert(newProject)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ProjectRowView(project: .preview)
}

#Preview {
    NavigationStack {
        ProjectDetailView(project: .preview)
    }
}

#Preview {
    NewProjectSheet()
}
