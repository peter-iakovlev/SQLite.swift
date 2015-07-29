//
// SQLite.swift
// https://github.com/stephencelis/SQLite.swift
// Copyright (c) 2014-2015 Stephen Celis.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import sqlcipher

/// A connection (handle) to SQLite.
public final class Database {

    /// The location of a SQLite database.
    public enum Location {

        /// An in-memory database (equivalent to `.URI(":memory:")`).
        ///
        /// See: <https://www.sqlite.org/inmemorydb.html#sharedmemdb>
        case InMemory

        /// A temporary, file-backed database (equivalent to `.URI("")`).
        ///
        /// See: <https://www.sqlite.org/inmemorydb.html#temp_db>
        case Temporary

        /// A database located at the given URI filename (or path).
        ///
        /// See: <https://www.sqlite.org/uri.html>
        ///
        /// - parameter filename: A URI filename
        case URI(String)

    }

    internal var handle: COpaquePointer = nil

    /// Whether or not the database was opened in a read-only state.
    public var readonly: Bool { return sqlite3_db_readonly(handle, nil) == 1 }

    /// Initializes a new connection to a database.
    ///
    /// - parameter location: The location of the database. Creates a new database if
    ///                  it doesn’t already exist (unless in read-only mode).
    ///
    ///                  Default: `.InMemory`.
    ///
    /// - parameter readonly: Whether or not to open the database in a read-only
    ///                  state.
    ///
    ///                  Default: `false`.
    ///
    /// - returns: A new database connection.
    public init(_ location: Location = .InMemory, readonly: Bool = false) {
        let flags = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        `try` { sqlite3_open_v2(location.description, &self.handle, flags | SQLITE_OPEN_FULLMUTEX, nil) }
    }

    /// Initializes a new connection to a database.
    ///
    /// - parameter filename: The location of the database. Creates a new database if
    ///                  it doesn’t already exist (unless in read-only mode).
    ///
    /// - parameter readonly: Whether or not to open the database in a read-only
    ///                  state.
    ///
    ///                  Default: `false`.
    ///
    /// - returns: A new database connection.
    public convenience init(_ filename: String, readonly: Bool = false) {
        self.init(.URI(filename), readonly: readonly)
    }

    deinit { `try` { sqlite3_close(self.handle) } } // sqlite3_close_v2 in Yosemite/iOS 8?

    // MARK: -

    /// The last rowid inserted into the database via this connection.
    public var lastInsertRowid: Int64? {
        let rowid = sqlite3_last_insert_rowid(handle)
        return rowid == 0 ? nil : rowid
    }

    /// The last number of changes (inserts, updates, or deletes) made to the
    /// database via this connection.
    public var changes: Int {
        return Int(sqlite3_changes(handle))
    }

    /// The total number of changes (inserts, updates, or deletes) made to the
    /// database via this connection.
    public var totalChanges: Int { return Int(sqlite3_total_changes(handle)) }

    // MARK: - Execute

    /// Executes a batch of SQL statements.
    ///
    /// - parameter SQL: A batch of zero or more semicolon-separated SQL statements.
    public func execute(SQL: String) {
        `try` { sqlite3_exec(self.handle, SQL, nil, nil, nil) }
    }
    
    public func adjustChunkSize() {
        `try` {
            var value: Int32 = 1 * 1024 * 1024
            sqlite3_file_control(self.handle, nil, SQLITE_FCNTL_CHUNK_SIZE, &value)
            return SQLITE_OK
        }
    }

    // MARK: - Prepare

    /// Prepares a single SQL statement (with optional parameter bindings).
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: A prepared statement.
    public func prepare(statement: String, _ bindings: Binding?...) -> Statement {
        if !bindings.isEmpty { return prepare(statement, bindings) }
        return Statement(self, statement)
    }
    
    var cachedStatements: [String : Statement] = [:]
    
    public func prepareCached(statement: String) -> Statement {
        if let cached = self.cachedStatements[statement] {
            return cached
        } else {
            let cached = Statement(self, statement)
            self.cachedStatements[statement] = cached
            return cached
        }
    }

    /// Prepares a single SQL statement and binds parameters to it.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: A prepared statement.
    public func prepare(statement: String, _ bindings: [Binding?]) -> Statement {
        return prepare(statement).bind(bindings)
    }

    /// Prepares a single SQL statement and binds parameters to it.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A dictionary of named parameters to bind to the
    ///                   statement.
    ///
    /// - returns: A prepared statement.
    public func prepare(statement: String, _ bindings: [String: Binding?]) -> Statement {
        return prepare(statement).bind(bindings)
    }

    // MARK: - Run

    /// Runs a single SQL statement (with optional parameter bindings).
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: The statement.
    public func run(statement: String, _ bindings: Binding?...) -> Statement {
        return run(statement, bindings)
    }

    /// Prepares, binds, and runs a single SQL statement.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: The statement.
    public func run(statement: String, _ bindings: [Binding?]) -> Statement {
        return prepare(statement).run(bindings)
    }

    /// Prepares, binds, and runs a single SQL statement.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A dictionary of named parameters to bind to the
    ///                   statement.
    ///
    /// - returns: The statement.
    public func run(statement: String, _ bindings: [String: Binding?]) -> Statement {
        return prepare(statement).run(bindings)
    }

    // MARK: - Scalar

    /// Runs a single SQL statement (with optional parameter bindings),
    /// returning the first value of the first row.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: The first value of the first row returned.
    public func scalar(statement: String, _ bindings: Binding?...) -> Binding? {
        return scalar(statement, bindings)
    }

    /// Prepares, binds, and runs a single SQL statement, returning the first
    /// value of the first row.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A list of parameters to bind to the statement.
    ///
    /// - returns: The first value of the first row returned.
    public func scalar(statement: String, _ bindings: [Binding?]) -> Binding? {
        return prepare(statement).scalar(bindings)
    }

    /// Prepares, binds, and runs a single SQL statement, returning the first
    /// value of the first row.
    ///
    /// - parameter statement: A single SQL statement.
    ///
    /// - parameter bindings:  A dictionary of named parameters to bind to the
    ///                   statement.
    ///
    /// - returns: The first value of the first row returned.
    public func scalar(statement: String, _ bindings: [String: Binding?]) -> Binding? {
        return prepare(statement).scalar(bindings)
    }

    // MARK: - Transactions

    /// The mode in which a transaction acquires a lock.
    public enum TransactionMode: String {

        /// Defers locking the database till the first read/write executes.
        case Deferred = "DEFERRED"

        /// Immediately acquires a reserved lock on the database.
        case Immediate = "IMMEDIATE"

        /// Immediately acquires an exclusive lock on all databases.
        case Exclusive = "EXCLUSIVE"

    }

    /// The result of a transaction.
    public enum TransactionResult: String {

        /// Commits a transaction.
        case Commit = "COMMIT TRANSACTION"

        /// Rolls a transaction back.
        case Rollback = "ROLLBACK TRANSACTION"

    }

    /// Starts a new transaction with the given mode.
    ///
    /// - parameter mode: The mode in which a transaction acquires a lock.
    ///
    ///              Default: `.Deferred`
    ///
    /// - returns: The BEGIN TRANSACTION statement.
    public func transaction(_ mode: TransactionMode = .Deferred) -> Statement {
        return run("BEGIN \(mode.rawValue) TRANSACTION")
    }

    /// Runs a transaction with the given savepoint name (if omitted, it will
    /// generate a UUID).
    ///
    /// - parameter mode:  The mode in which a transaction acquires a lock.
    ///
    ///               Default: `.Deferred`
    ///
    /// - parameter block: A closure to run SQL statements within the transaction.
    ///               Should return a TransactionResult depending on success or
    ///               failure.
    ///
    /// - returns: The COMMIT or ROLLBACK statement.
    public func transaction(_ mode: TransactionMode = .Deferred, @noescape _ block: (txn: Statement) -> TransactionResult) -> Statement {
        return run(block(txn: transaction(mode)).rawValue)
    }

    /// Commits the current transaction (or, if a savepoint is open, releases
    /// the current savepoint).
    ///
    /// - parameter all: Only applicable if a savepoint is open. If true, commits all
    ///             open savepoints, otherwise releases the current savepoint.
    ///
    ///             Default: `false`
    ///
    /// - returns: The COMMIT (or RELEASE) statement.
    public func commit(all: Bool = false) -> Statement {
        if !savepointStack.isEmpty && !all {
            return release()
        }
        savepointStack.removeAll()
        return run(TransactionResult.Commit.rawValue)
    }

    /// Rolls back the current transaction (or, if a savepoint is open, the
    /// current savepoint).
    ///
    /// - parameter all: Only applicable if a savepoint is open. If true, rolls back
    ///             all open savepoints, otherwise rolls back the current
    ///             savepoint.
    ///
    ///             Default: `false`
    ///
    /// - returns: The ROLLBACK statement.
    public func rollback(all: Bool = false) -> Statement {
        if !savepointStack.isEmpty && !all {
            return rollback(savepointStack.removeLast())
        }
        savepointStack.removeAll()
        return run(TransactionResult.Rollback.rawValue)
    }

    // MARK: - Savepoints

    /// The result of a savepoint.
    public enum SavepointResult {

        /// Releases a savepoint.
        case Release

        /// Rolls a savepoint back.
        case Rollback

    }

    private var savepointStack = [String]()

    /// Starts a new transaction with the given savepoint name.
    ///
    /// - parameter savepointName: A unique identifier for the savepoint.
    ///
    /// - returns: The SAVEPOINT statement.
    public func savepoint(_ savepointName: String? = nil) -> Statement {
        let name = savepointName ?? NSUUID().UUIDString
        savepointStack.append(name)
        return run("SAVEPOINT \(quote(literal: name))")
    }

    /// Runs a transaction with the given savepoint name (if omitted, it will
    /// generate a UUID).
    ///
    /// - parameter savepointName: A unique identifier for the savepoint (optional).
    ///
    /// - parameter block:         A closure to run SQL statements within the
    ///                       transaction. Should return a SavepointResult
    ///                       depending on success or failure.
    ///
    /// - returns: The RELEASE or ROLLBACK statement.
    public func savepoint(_ savepointName: String? = nil, @noescape _ block: (txn: Statement) -> SavepointResult) -> Statement {
        switch block(txn: savepoint(savepointName)) {
        case .Release:
            return release()
        case .Rollback:
            return rollback()
        }
    }

    /// Releases a savepoint with the given savepoint name (or the most
    /// recently-opened savepoint).
    ///
    /// - parameter savepointName: A unique identifier for the savepoint (optional).
    ///
    /// - returns: The RELEASE SAVEPOINT statement.
    public func release(_ savepointName: String? = nil) -> Statement {
        let name = savepointName ?? savepointStack.removeLast()
        if let idx = savepointStack.indexOf(name) { savepointStack.removeRange(idx..<savepointStack.count) }
        return run("RELEASE SAVEPOINT \(quote(literal: name))")
    }

    /// Rolls a transaction back to the given savepoint name.
    ///
    /// - parameter savepointName: A unique identifier for the savepoint.
    ///
    /// - returns: The ROLLBACK TO SAVEPOINT statement.
    public func rollback(savepointName: String) -> Statement {
        if let idx = savepointStack.indexOf(savepointName) { savepointStack.removeRange(idx..<savepointStack.count) }
        return run("ROLLBACK TO SAVEPOINT \(quote(literal: savepointName))")
    }

    /// Interrupts any long-running queries.
    public func interrupt() {
        sqlite3_interrupt(handle)
    }

    // MARK: - Handlers

    /// Sets a busy timeout to retry after encountering a busy signal (lock).
    ///
    /// - parameter ms: Milliseconds to wait before retrying.
    public func busyTimeout(ms: Int) {
        sqlite3_busy_timeout(handle, Int32(ms))
    }

    /// Sets a busy handler to call after encountering a busy signal (lock).
    ///
    /// - parameter callback: This block is executed during a lock in which a busy
    ///                  error would otherwise be returned. It’s passed the
    ///                  number of times it’s been called for this lock. If it
    ///                  returns true, it will try again. If it returns false,
    ///                  no further attempts will be made.
    public func busyHandler(callback: ((tries: Int) -> Bool)?) {
        `try` {
            if let callback = callback {
                self.busyHandler = { callback(tries: Int($0)) ? 1 : 0 }
            } else {
                self.busyHandler = nil
            }
            return _SQLiteBusyHandler(self.handle, self.busyHandler)
        }
    }
    private var busyHandler: _SQLiteBusyHandlerCallback?

    /// Sets a handler to call when a statement is executed with the compiled
    /// SQL.
    ///
    /// - parameter callback: This block is invoked when a statement is executed with
    ///                  the compiled SQL as its argument. E.g., pass `println`
    ///                  to act as a logger.
    public func trace(callback: ((SQL: String) -> Void)?) {
        if let callback = callback {
            trace = { callback(SQL: String.fromCString($0)!) }
        } else {
            trace = nil
        }
        _SQLiteTrace(handle, trace)
    }
    private var trace: _SQLiteTraceCallback?

    /// An SQL operation passed to update callbacks.
    public enum Operation {

        /// An INSERT operation.
        case Insert

        /// An UPDATE operation.
        case Update

        /// A DELETE operation.
        case Delete

        private static func fromRawValue(rawValue: Int32) -> Operation {
            switch rawValue {
            case SQLITE_INSERT:
                return .Insert
            case SQLITE_UPDATE:
                return .Update
            case SQLITE_DELETE:
                return .Delete
            default:
                fatalError("unhandled operation code: \(rawValue)")
            }
        }

    }

    /// Registers a callback to be invoked whenever a row is inserted, updated,
    /// or deleted in a rowid table.
    ///
    /// - parameter callback: A callback invoked with the `Operation` (one
    ///                  of `.Insert`, `.Update`, or `.Delete`), database name,
    ///                  table name, and rowid.
    public func updateHook(callback: ((operation: Operation, db: String, table: String, rowid: Int64) -> Void)?) {
        if let callback = callback {
            updateHook = { operation, db, table, rowid in
                callback(
                    operation: .fromRawValue(operation),
                    db: String.fromCString(db)!,
                    table: String.fromCString(table)!,
                    rowid: rowid
                )
            }
        } else {
            updateHook = nil
        }
        _SQLiteUpdateHook(handle, updateHook)
    }
    private var updateHook: _SQLiteUpdateHookCallback?

    /// Registers a callback to be invoked whenever a transaction is committed.
    ///
    /// - parameter callback: A callback that must return `.Commit` or `.Rollback` to
    ///                  determine whether a transaction should be committed or
    ///                  not.
    public func commitHook(callback: (() -> TransactionResult)?) {
        if let callback = callback {
            commitHook = { callback() == .Commit ? 0 : 1 }
        } else {
            commitHook = nil
        }
        _SQLiteCommitHook(handle, commitHook)
    }
    private var commitHook: _SQLiteCommitHookCallback?

    /// Registers a callback to be invoked whenever a transaction rolls back.
    ///
    /// - parameter callback: A callback invoked when a transaction is rolled back.
    public func rollbackHook(callback: (() -> Void)?) {
        rollbackHook = callback.map { $0 }
        _SQLiteRollbackHook(handle, rollbackHook)
    }
    private var rollbackHook: _SQLiteRollbackHookCallback?

    /// Creates or redefines a custom SQL function.
    ///
    /// - parameter function:      The name of the function to create or redefine.
    ///
    /// - parameter argc:          The number of arguments that the function takes.
    ///                       If this parameter is `-1`, then the SQL function
    ///                       may take any number of arguments.
    ///
    ///                       Default: `-1`
    ///
    /// - parameter deterministic: Whether or not the function is deterministic. If
    ///                       the function always returns the same result for a
    ///                       given input, SQLite can make optimizations.
    ///
    ///                       Default: `false`
    ///
    /// - parameter block:         A block of code to run when the function is
    ///                       called. The block is called with an array of raw
    ///                       SQL values mapped to the function’s parameters and
    ///                       should return a raw SQL value (or nil).
    public func create(function function: String, argc: Int = -1, deterministic: Bool = false, _ block: (args: [Binding?]) -> Binding?) {
        `try` {
            if self.functions[function] == nil { self.functions[function] = [:] }
            self.functions[function]?[argc] = { context, argc, argv in
                let arguments: [Binding?] = (0..<Int(argc)).map { idx in
                    let value = argv[idx]
                    switch sqlite3_value_type(value) {
                    case SQLITE_BLOB:
                        let bytes = sqlite3_value_blob(value)
                        let length = sqlite3_value_bytes(value)
                        return Blob(bytes: bytes, length: Int(length))
                    case SQLITE_FLOAT:
                        return sqlite3_value_double(value)
                    case SQLITE_INTEGER:
                        return sqlite3_value_int64(value)
                    case SQLITE_NULL:
                        return nil
                    case SQLITE_TEXT:
                        return String.fromCString(UnsafePointer(sqlite3_value_text(value)))!
                    case let type:
                        fatalError("unsupported value type: \(type)")
                    }
                }
                let result = block(args: arguments)
                if let result = result as? Blob {
                    sqlite3_result_blob(context, result.bytes, Int32(result.length), nil)
                } else if let result = result as? Double {
                    sqlite3_result_double(context, result)
                } else if let result = result as? Int64 {
                    sqlite3_result_int64(context, result)
                } else if let result = result as? String {
                    sqlite3_result_text(context, result, Int32(result.characters.count), SQLITE_TRANSIENT)
                } else if result == nil {
                    sqlite3_result_null(context)
                } else {
                    fatalError("unsupported result type: \(result)")
                }
            }
            return _SQLiteCreateFunction(self.handle, function, Int32(argc), deterministic ? 1 : 0, self.functions[function]?[argc])
        }
    }
    private var functions = [String: [Int: _SQLiteCreateFunctionCallback]]()

    /// The return type of a collation comparison function.
    public typealias ComparisonResult = NSComparisonResult

    /// Defines a new collating sequence.
    ///
    /// - parameter collation: The name of the collation added.
    ///
    /// - parameter block:     A collation function that takes two strings and
    ///                   returns the comparison result.
    public func create(collation collation: String, _ block: (lhs: String, rhs: String) -> ComparisonResult) {
        `try` {
            self.collations[collation] = { lhs, rhs in
                return Int32(block(lhs: String.fromCString(lhs)!, rhs: String.fromCString(rhs)!).rawValue)
            }
            return _SQLiteCreateCollation(self.handle, collation, self.collations[collation])
        }
    }
    private var collations = [String: _SQLiteCreateCollationCallback]()

    // MARK: - Error Handling

    /// Returns the last error produced on this connection.
    public var lastError: String? {
        let errorCode = sqlite3_errcode(handle)
        if errorCode == SQLITE_OK || errorCode == SQLITE_ROW || errorCode == SQLITE_DONE {
            return nil
        }
        return String.fromCString(sqlite3_errmsg(handle))!
    }

    internal func `try`(block: () -> Int32) {
        perform { if block() != SQLITE_OK { assertionFailure("\(self.lastError!)") } }
    }

    // MARK: - Threading

    //private let queue = dispatch_queue_create("SQLite.Database", DISPATCH_QUEUE_SERIAL)

    internal func perform(block: () -> Void) { block() /*dispatch_sync(queue, block)*/ }

}

// MARK: - Printable
extension Database: CustomStringConvertible {

    public var description: String {
        return String.fromCString(sqlite3_db_filename(handle, nil))!
    }

}

extension Database.Location: CustomStringConvertible {

    public var description: String {
        switch self {
        case .InMemory:
            return ":memory:"
        case .Temporary:
            return ""
        case .URI(let URI):
            return URI
        }
    }

}

internal func quote(literal literal: String) -> String {
    return quote(literal, mark: "'")
}

internal func quote(identifier identifier: String) -> String {
    return quote(identifier, mark: "\"")
}

private func quote(string: String, mark: Character) -> String {
    let escaped = string.characters.reduce("") { string, character in
        string + (character == mark ? "\(mark)\(mark)" : "\(character)")
    }
    return "\(mark)\(escaped)\(mark)"
}
