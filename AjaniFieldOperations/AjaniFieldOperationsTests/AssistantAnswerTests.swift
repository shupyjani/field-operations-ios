import Foundation
import Testing
@testable import AjaniFieldOperations

@Suite("Counts and status")
struct AssistantCountTests {
    @Test("Reports how many visits remain")
    func reportsRemaining() {
        let answer = AssistantFixtures.ask("How many visits are left?")

        #expect(answer.kind == .remaining)
        #expect(answer.text == "5 visits remain on today\u{2019}s round.")
    }

    @Test("Reports completed against the total")
    func reportsCompleted() {
        let answer = AssistantFixtures.ask("How many visits have I completed?")

        #expect(answer.kind == .counts)
        #expect(answer.text == "2 of 7 visits are complete.")
    }

    @Test("Keeps completed and cancelled apart in the round summary")
    func keepsOutcomesApart() {
        var visits = AssistantFixtures.visits
        let plannedIndex = visits.firstIndex { $0.status == .planned } ?? 3
        visits[plannedIndex].status = .cancelled
        visits[plannedIndex].cancellation = Cancellation(reason: .familyCancelled)

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("How many visits are on the round?")

        #expect(answer.text.contains("2 completed"))
        #expect(answer.text.contains("1 cancelled"))
        #expect(answer.text.contains("3 of 7 visits resolved"))
    }

    @Test("Lists which visits are cancelled")
    func listsCancelled() {
        var visits = AssistantFixtures.visits
        let index = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[index].status = .cancelled
        visits[index].cancellation = Cancellation(reason: .clientUnavailable)

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("Which visits are cancelled?")

        #expect(answer.kind == .statusList)
        #expect(answer.text.contains("Ivor Bankole"))
        #expect(answer.text.contains("1 visit"))
    }

    @Test("Says plainly when no visit holds a status")
    func reportsEmptyStatus() {
        let answer = AssistantFixtures.ask("Which visits are cancelled?")

        #expect(answer.kind == .statusList)
        #expect(answer.text == "No visit on today\u{2019}s round is cancelled.")
    }

    @Test("Lists the planned visits in schedule order")
    func listsPlanned() {
        let answer = AssistantFixtures.ask("Show my planned visits.")

        #expect(answer.kind == .statusList)
        #expect(answer.text.contains("4 visits planned"))
        // Schedule order, not array order.
        let ivor = answer.text.range(of: "Ivor Bankole")
        let sunita = answer.text.range(of: "Sunita Kaur")
        #expect(ivor != nil && sunita != nil)
        #expect(ivor!.lowerBound < sunita!.lowerBound)
    }
}

@Suite("The visit in hand")
struct AssistantNextVisitTests {
    @Test("Names the active visit when one is on site")
    func namesActiveVisit() {
        let answer = AssistantFixtures.ask("Which visit is currently active?")

        #expect(answer.kind == .active)
        #expect(answer.text == "Priya Raman is your current active visit, at 9:40–10:40 (Arrived).")
    }

    @Test("An ongoing question reaches the same answer")
    func ongoingIsTheSameQuestion() {
        #expect(AssistantFixtures.ask("Is there any ongoing?").text
                == AssistantFixtures.ask("Which visit is currently active?").text)
    }

    @Test("The active visit is next, ahead of an earlier planned one")
    func activeVisitLeads() {
        let answer = AssistantFixtures.ask("Who is my next visit?")

        #expect(answer.kind == .next)
        #expect(answer.text.contains("Priya Raman"))
    }

    @Test("Falls back to the earliest planned visit once nothing is active")
    func fallsBackToEarliestPlanned() {
        var visits = AssistantFixtures.visits
        let index = visits.firstIndex { $0.status == .arrived } ?? 2
        visits[index].status = .completed

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("Who is my next visit?")

        #expect(answer.text.contains("Ivor Bankole"))
        #expect(answer.text.contains("11:00–11:45"))
    }

    @Test("Says so when nothing is left waiting")
    func reportsRoundComplete() {
        var visits = AssistantFixtures.visits
        for index in visits.indices { visits[index].status = .completed }

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("Who is my next visit?")

        #expect(answer.text == "Nothing is left waiting on today\u{2019}s round.")
    }

    @Test("A cancelled visit is never the visit in hand")
    func skipsCancelled() {
        var visits = AssistantFixtures.visits
        let arrived = visits.firstIndex { $0.status == .arrived } ?? 2
        visits[arrived].status = .completed
        let ivor = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[ivor].status = .cancelled
        visits[ivor].cancellation = Cancellation(reason: .familyCancelled)

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("Who is my next visit?")

        #expect(answer.text.contains("Halina Nowak"))
    }
}

@Suite("People and selection")
struct AssistantPersonTests {
    @Test("Finds a person by full name")
    func findsByFullName() {
        let answer = AssistantFixtures.ask("Find Ivor Bankole.")

        #expect(answer.kind == .person)
        #expect(answer.text.contains("Ivor Bankole"))
        #expect(answer.text.contains("Wellbeing and mobility"))
    }

    @Test("Finds a person by first name alone")
    func findsByFirstName() {
        #expect(AssistantFixtures.ask("Tell me about Priya").text.contains("Priya Raman"))
    }

    @Test("Reads a single recorded field when one is asked for")
    func readsOneField() {
        #expect(AssistantFixtures.ask("What is Priya's address?").text.contains("21 Halesmere Gardens"))
        #expect(AssistantFixtures.ask("What is Halina's status?").text.contains("Planned"))
        #expect(AssistantFixtures.ask("What is Sunita's reference?").text.contains("AV-1047"))
    }

    @Test("Says when a name matches nobody on the round")
    func reportsUnknownPerson() {
        let answer = AssistantFixtures.ask("Tell me about Nicholas")

        #expect(answer.kind == .notFound)
        #expect(answer.text.contains("Nicholas"))
    }

    @Test("Asks which person was meant when a name is shared")
    func asksWhichPerson() {
        var visits = AssistantFixtures.visits
        visits[3] = Visit(
            id: visits[3].id,
            reference: visits[3].reference,
            clientName: "Priya Chandra",
            visitType: visits[3].visitType,
            location: visits[3].location,
            scheduledStart: visits[3].scheduledStart,
            scheduledEnd: visits[3].scheduledEnd,
            priority: visits[3].priority,
            operationalNotes: visits[3].operationalNotes,
            tasks: visits[3].tasks,
            status: visits[3].status
        )

        let answer = LocalAssistant(round: AssistantFixtures.round(visits: visits))
            .answer("What time is Priya's visit?")

        #expect(answer.kind == .ambiguous)
        #expect(answer.text.contains("Priya Raman"))
        #expect(answer.text.contains("Priya Chandra"))
    }

    @Test("A question naming nobody proposes nobody")
    func proposesNobody() {
        // "related" and "similar" look like names and are not.
        #expect(AssistantPeople.recognise("Do I have any wound related task today?", in: AssistantFixtures.visits) == nil)
    }

    @Test("Reports the priority visit")
    func reportsPriority() {
        let answer = AssistantFixtures.ask("Which visit is marked Priority?")

        #expect(answer.kind == .priority)
        #expect(answer.text.contains("Priya Raman"))
        #expect(answer.text.contains("1 visit"))
    }
}

@Suite("Tasks")
struct AssistantTaskTests {
    @Test("Counts the tasks on one person's checklist")
    func countsOnePersonsTasks() {
        let answer = AssistantFixtures.ask("How many tasks does Priya have?")

        #expect(answer.kind == .taskCount)
        #expect(answer.text.contains("3 tasks"))
        #expect(answer.text.contains("1 ticked"))
        #expect(answer.text.contains("2 unticked"))
    }

    @Test("Lists what remains for one person")
    func listsRemainingTasks() {
        let answer = AssistantFixtures.ask("What tasks remain for Priya Raman?")

        #expect(answer.kind == .tasks)
        #expect(answer.text.contains("Check wound dressing"))
        #expect(answer.text.contains("Confirm follow-up appointment is diarised"))
        #expect(!answer.text.contains("Review discharge notes"))
    }

    @Test("Counts every task on the round")
    func countsAllTasks() {
        let answer = AssistantFixtures.ask("How many tasks are there in total today?")

        #expect(answer.kind == .taskTotals)
        #expect(answer.text.contains("21 tasks"))
    }

    @Test("Counts work still due separately from unchecked records")
    func separatesDueFromUnchecked() {
        var visits = AssistantFixtures.visits
        let index = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[index].status = .cancelled
        visits[index].cancellation = Cancellation(reason: .familyCancelled)
        let round = AssistantFixtures.round(visits: visits)

        let due = LocalAssistant(round: round).answer("How many tasks are still due?")
        let unchecked = LocalAssistant(round: round).answer("How many unchecked tasks are there?")

        // The round holds 21 tasks with 7 ticked, so 14 are unchecked whatever
        // becomes of their visits. Cancelling Ivor's visit takes his three
        // unticked tasks out of the work still due — they remain unchecked
        // records, but nothing further happens at that address.
        #expect(due.text.contains("11 tasks"))
        #expect(unchecked.text.contains("14 tasks"))
    }

    @Test("Searches every checklist for an activity")
    func searchesChecklists() {
        let answer = AssistantFixtures.ask("Are there any wound related tasks today?")

        #expect(answer.kind == .taskSearch)
        #expect(answer.text.contains("Priya Raman"))
        #expect(answer.text.contains("Check wound dressing"))
        #expect(answer.text.contains("unchecked"))
        #expect(answer.text.contains("Photograph not required"))
    }

    @Test("Finds a walking task through ordinary inflection")
    func findsWalkingTask() {
        let answer = AssistantFixtures.ask("Does anyone have a walking task?")

        #expect(answer.kind == .taskSearch)
        #expect(answer.text.contains("Ivor Bankole"))
        #expect(answer.text.contains("Walk the hallway circuit twice"))
    }

    @Test("Says plainly when no checklist matches")
    func reportsNoMatch() {
        let answer = AssistantFixtures.ask("Does anyone have a swimming task?")

        #expect(answer.kind == .taskSearch)
        #expect(answer.text == "No task on today\u{2019}s round matches that.")
    }
}

@Suite("Schedule and notes")
struct AssistantScheduleTests {
    @Test("Reads one person's scheduled window")
    func readsScheduledWindow() {
        let answer = AssistantFixtures.ask("What time is Ivor's visit?")

        #expect(answer.kind == .schedule)
        #expect(answer.text.contains("11:00–11:45"))
    }

    @Test("Reads a visit's scheduled duration")
    func readsDuration() {
        let answer = AssistantFixtures.ask("How long is Ivor's whole visit?")

        #expect(answer.kind == .duration)
        #expect(answer.text.contains("45 min"))
        #expect(answer.text.contains("11:00–11:45"))
    }

    @Test("Reads a recorded travel estimate without recalculating a route")
    func readsTravel() {
        let answer = AssistantFixtures.ask("What travel is recorded for Priya?")

        #expect(answer.kind == .travel)
        #expect(answer.text.contains("15 min"))
    }

    @Test("Reports the shift window")
    func reportsShift() {
        let answer = AssistantFixtures.ask("When does my shift finish?")

        #expect(answer.kind == .schedule)
        #expect(answer.text.contains("7:30–15:45"))
    }

    @Test("Reads one person's operational notes")
    func readsNotes() {
        let answer = AssistantFixtures.ask("What notes are recorded for Priya?")

        #expect(answer.kind == .notes)
        #expect(answer.text.contains("escalate any new pain"))
    }
}

@Suite("Completion order")
struct AssistantCompletionOrderTests {
    @Test("Qualifies a schedule-based answer when the session watched nothing")
    func qualifiesSeedCompletions() {
        let answer = AssistantFixtures.ask("Which visit did I just finish?")

        #expect(answer.kind == .completion)
        #expect(answer.text.contains("Desmond Achebe"))
        #expect(answer.text.contains("do not say which was completed last"))
    }

    @Test("Names the visit the session actually watched complete")
    func namesObservedCompletion() {
        var visits = AssistantFixtures.visits
        let index = visits.firstIndex { $0.reference == "AV-1043" } ?? 2
        visits[index].status = .completed

        let round = AssistantFixtures.round(visits: visits, completionOrder: [visits[index].id])
        let answer = LocalAssistant(round: round).answer("Which visit did I just finish?")

        #expect(answer.text.contains("Priya Raman"))
        #expect(answer.text.contains("most recently this session"))
        #expect(!answer.text.contains("do not say"))
    }

    @Test("Reports the most recent of several observed completions")
    func reportsLatestObserved() {
        var visits = AssistantFixtures.visits
        let priya = visits.firstIndex { $0.reference == "AV-1043" } ?? 2
        let ivor = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[priya].status = .completed
        visits[ivor].status = .completed

        let round = AssistantFixtures.round(
            visits: visits,
            completionOrder: [visits[priya].id, visits[ivor].id]
        )

        #expect(LocalAssistant(round: round).answer("Which visit did I just finish?").text.contains("Ivor Bankole"))
    }
}

@Suite("Cancellation records")
struct AssistantCancellationRecordTests {
    private func cancelledRound(reason: CancellationReason, note: String = "") -> AssistantRound {
        var visits = AssistantFixtures.visits
        let index = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[index].status = .cancelled
        visits[index].cancellation = Cancellation(reason: reason, note: note)
        return AssistantFixtures.round(visits: visits)
    }

    @Test("Reads back the recorded reason")
    func readsReason() {
        let answer = LocalAssistant(round: cancelledRound(reason: .officeInstruction))
            .answer("Why was Ivor's visit cancelled?")

        #expect(answer.kind == .cancellation)
        #expect(answer.text.contains("Office instruction"))
    }

    @Test("Reports the note beside the reason, as a separate field")
    func reportsNoteSeparately() {
        let answer = LocalAssistant(round: cancelledRound(reason: .other, note: "Road closed"))
            .answer("Why was Ivor's visit cancelled?")

        #expect(answer.text.contains("Reason: Other"))
        #expect(answer.text.contains("Note: Road closed"))
    }

    @Test("Asking which reasons the app offers is a question about the control")
    func reasonsMenuIsGuidance() {
        let answer = LocalAssistant(round: cancelledRound(reason: .familyCancelled))
            .answer("What reasons can I give for cancelling a visit?")

        #expect(answer.kind == .guidance)
        #expect(answer.text.contains("Family cancelled"))
    }

    @Test("A visit with no cancellation says so rather than inventing one")
    func reportsNoCancellation() {
        let answer = AssistantFixtures.ask("Why was Priya's visit cancelled?")

        #expect(answer.text.contains("records no cancellation"))
    }
}

@Suite("Follow-up context")
struct AssistantFollowUpTests {
    @Test("A task follow-up reads the current record, not the previous reply")
    func followsUpOnATask() {
        let first = AssistantFixtures.ask("Does anyone have a walking task?")
        let context = first.selection

        let second = AssistantFixtures.ask("Has that task been completed?", context: context)

        #expect(second.kind == .taskDetail)
        #expect(second.text.contains("No."))
        #expect(second.text.contains("Walk the hallway circuit twice"))
        #expect(second.text.contains("unchecked"))
    }

    @Test("The follow-up reflects a task ticked since the first answer")
    func followUpReflectsCurrentState() {
        let first = AssistantFixtures.ask("Does anyone have a walking task?")
        let context = first.selection

        var visits = AssistantFixtures.visits
        let ivor = visits.firstIndex { $0.reference == "AV-1044" } ?? 3
        visits[ivor].tasks[0].isComplete = true

        let second = LocalAssistant(round: AssistantFixtures.round(visits: visits), context: context)
            .answer("Is it still outstanding?")

        // The question asks whether it is outstanding, and it is not: the lead
        // answers that question rather than the state it reports.
        #expect(second.text.contains("No."))
        #expect(second.text.contains("ticked"))
        #expect(!second.text.contains("unchecked"))
    }

    @Test("Reads a recorded repetition count from the task's own wording")
    func readsRepetitions() {
        let first = AssistantFixtures.ask("Does anyone have a walking task?")
        let second = AssistantFixtures.ask("How many times should it be walked?", context: first.selection)

        #expect(second.text.contains("repetitions: 2 times"))
    }

    @Test("A missing duration never inherits the visit's own")
    func neverInheritsVisitDuration() {
        let first = AssistantFixtures.ask("Does anyone have a walking task?")
        let second = AssistantFixtures.ask("How long should that take?", context: first.selection)

        #expect(second.text.contains("does not specify a duration"))
        // Ivor's visit is 45 minutes; the task must not borrow it.
        #expect(!second.text.contains("45"))
    }

    @Test("Reads a duration the task does record")
    func readsRecordedDuration() {
        let first = AssistantFixtures.ask("What tasks does Sunita have?")
        let second = AssistantFixtures.ask("How long are the seated exercises?", context: first.selection)

        #expect(second.text.contains("10 minutes"))
    }

    @Test("Names the candidates when a choice would change the answer")
    func namesCandidatesWorthChoosingBetween() {
        let first = AssistantFixtures.ask("Which tasks mention exercises?")
        let second = AssistantFixtures.ask("How long?", context: first.selection)

        #expect(second.kind == .clarify)
        #expect(second.text.contains("Log how the exercises were tolerated"))
        #expect(second.text.contains("Seated exercises, ten minutes"))
    }

    @Test("An ordinal answers a clarification the assistant has just asked")
    func ordinalAnswersTheClarification() {
        let first = AssistantFixtures.ask("Which tasks mention exercises?")
        let clarify = AssistantFixtures.ask("How long?", context: first.selection)
        let resolved = AssistantFixtures.ask("How long is the second task?", context: clarify.selection)

        #expect(resolved.kind == .taskDetail)
        #expect(resolved.text.contains("10 minutes"))
    }

    @Test("An ordinal beyond the list is said to be unresolvable")
    func ordinalBeyondTheListIsRefused() {
        let first = AssistantFixtures.ask("Which tasks mention exercises?")
        let second = AssistantFixtures.ask("How long is the fifth task?", context: first.selection)

        #expect(second.kind == .clarify)
        #expect(second.text.contains("no task at that position"))
    }

    @Test("Nobody is asked to choose when no candidate records the property")
    func saysNoneRecordsRatherThanAsking() {
        let first = AssistantFixtures.ask("Do I have any medication task today?")
        let second = AssistantFixtures.ask("How long for?", context: first.selection)

        #expect(second.kind == .taskDetail)
        #expect(second.text.contains("None of"))
        #expect(second.text.contains("records a duration"))
        #expect(second.text.contains("Prompt morning medication"))
        // Desmond's visit is 8:45\u{2013}9:15; none of that may be borrowed.
        #expect(!second.text.contains("30 minutes"))
    }

    @Test("A refused request leaves the conversation's referent intact")
    func refusalPreservesContext() {
        let first = AssistantFixtures.ask("Does anyone have a walking task?")
        let context = first.selection

        // A boundary answer carries the same selection forward.
        let refusal = LocalAssistant(round: AssistantFixtures.round(), context: context)
            .answer("What dose should I give?")
        #expect(refusal.kind == .clinical)

        let resumed = AssistantFixtures.ask("Has that task been completed?", context: context)
        #expect(resumed.text.contains("Walk the hallway circuit twice"))
    }
}
