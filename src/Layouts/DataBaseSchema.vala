/*
* Copyright (c) 2017-2020 Alecaddd (https://alecaddd.com)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alessandro "Alecaddd" Castellani <castellani.ale@gmail.com>
*/

public class Sequeler.Layouts.DataBaseSchema : Gtk.Grid {
    public weak Sequeler.Window window { get; construct; }

    public Gtk.ListStore schema_list;
    public Gtk.ComboBox schema_list_combo;
    public Gtk.TreeIter iter;
    private bool reloading { get; set; default = false;}

    public Gee.HashMap<int, string> schemas;
    private ulong handler_id = 0;

    public Gtk.Stack stack;
    public Gtk.ScrolledWindow scroll;
    private Gda.DataModel? schema_table;
    public Sequeler.Widgets.SourceList.ExpandableItem tables_category;
    public Sequeler.Widgets.SourceList source_list;

    private Gtk.Grid toolbar;
    private Gtk.Spinner spinner;
    public Gtk.Revealer revealer;
    public Gtk.SearchEntry search;
    public string search_text;

    private Gtk.Grid main_grid;
    private Gtk.Revealer main_revealer;
    private Sequeler.Partials.DataBasePanel db_panel;

    enum Column {
        SCHEMAS
    }

    public DataBaseSchema (Sequeler.Window main_window) {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            window: main_window,
            column_homogeneous: true
        );
    }

    construct {
        var dropdown_area = new Gtk.Grid ();
        dropdown_area.column_homogeneous = false;
        dropdown_area.get_style_context ().add_class ("library-titlebar");

        var cell = new Gtk.CellRendererText ();

        schema_list = new Gtk.ListStore (1, typeof (string));

        schema_list_combo = new Gtk.ComboBox.with_model (schema_list);
        schema_list_combo.hexpand = true;
        schema_list_combo.pack_start (cell, false);
        schema_list_combo.set_attributes (cell, "text", Column.SCHEMAS);

        schema_list_combo.margin_top = schema_list_combo.margin_bottom = 9;
        schema_list_combo.margin_start = 9;

        reset_schema_combo.begin ();

        var search_btn = new Sequeler.Partials.HeaderBarButton ("system-search-symbolic", _("Search Tables"));
        search_btn.valign = Gtk.Align.CENTER;
        search_btn.clicked.connect (toggle_search_tables);

        dropdown_area.attach (schema_list_combo, 0, 0, 1, 1);
        dropdown_area.attach (search_btn, 1, 0, 1, 1);

        revealer = new Gtk.Revealer ();
        revealer.hexpand = true;
        revealer.reveal_child = false;

        search = new Gtk.SearchEntry ();
        search.placeholder_text = _("Search Tables\u2026");
        search.hexpand = true;
        search.margin = 9;
        search.search_changed.connect (on_search_tables);
        search.key_press_event.connect (key => {
            if (key.keyval == 65307) {
                search.set_text ("");
                toggle_search_tables ();
                return true;
            }
            return false;
        });
        revealer.add (search);

        scroll = new Gtk.ScrolledWindow (null, null);
        scroll.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
        scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
        scroll.vexpand = true;

        toolbar = new Gtk.Grid ();
        toolbar.get_style_context ().add_class ("library-toolbar");

        var reload_btn = new Sequeler.Partials.HeaderBarButton ("view-refresh-symbolic", _("Reload Tables"));
        reload_btn.clicked.connect (reload_schema);
        reload_btn.hexpand = true;
        reload_btn.halign = Gtk.Align.START;

        var add_table_btn = new Sequeler.Partials.HeaderBarButton ("list-add-symbolic", _("Add Table"));
        //  add_table_btn.clicked.connect (add_table);
        add_table_btn.sensitive = false;

        spinner = new Gtk.Spinner ();
        spinner.hexpand = true;
        spinner.vexpand = true;
        spinner.halign = Gtk.Align.CENTER;
        spinner.valign = Gtk.Align.CENTER;

        toolbar.attach (add_table_btn, 0, 0, 1, 1);
        toolbar.attach (new Gtk.Separator (Gtk.Orientation.VERTICAL), 1, 0, 1, 1);
        toolbar.attach (reload_btn, 2, 0, 1, 1);

        stack = new Gtk.Stack ();
        stack.hexpand = true;
        stack.vexpand = true;
        stack.add_named (scroll, "list");
        stack.add_named (spinner, "spinner");

        main_grid = new Gtk.Grid ();
        main_grid.attach (dropdown_area, 0, 0, 1, 1);
        main_grid.attach (revealer, 0, 1, 1, 1);
        main_grid.attach (stack, 0, 2, 1, 2);
        main_grid.attach (toolbar, 0, 4, 1, 1);

        main_revealer = new Gtk.Revealer ();
        main_revealer.reveal_child = true;
        main_revealer.transition_type = Gtk.RevealerTransitionType.CROSSFADE;
        main_revealer.add (main_grid);

        db_panel = new Sequeler.Partials.DataBasePanel (window);

        var overlay = new Gtk.Overlay ();
        overlay.add_overlay (db_panel);
        overlay.add (main_revealer);

        add (overlay);
    }

    public void start_spinner () {
        spinner.start ();
        stack.visible_child_name = "spinner";
    }

    public void stop_spinner () {
        spinner.stop ();
        stack.visible_child_name = "list";
    }

    private async void reset_schema_combo () {
        if (handler_id > 0) {
            schema_list_combo.disconnect (handler_id);
        }

        schema_list.clear ();
        schema_list.append (out iter);
        schema_list.set (iter, Column.SCHEMAS, _("- Select Database -"));
        schema_list_combo.set_active (0);
        schema_list_combo.sensitive = false;

        handler_id = schema_list_combo.changed.connect (() => {
            if (schema_list_combo.get_active () == 0) {
                return;
            }
            start_spinner ();
            init_populate_schema.begin (null);
        });
    }

    public async void init_populate_schema (Gda.DataModel? schema) {
        var database = window.data_manager.data["type"] == "SQLite" ? null : schemas[schema_list_combo.get_active ()];

        yield populate_schema (database, schema);
    }

    public async void reload_schema () {
        if (reloading) {
            debug ("still loading");
            return;
        }

        Gda.DataModel? schema = null;
        Gda.DataModelIter? _iter = null;
        reloading = true;

        schema = yield get_schema ();

        if (schema == null) {
            reloading = false;
            return;
        }

        yield reset_schema_combo ();

        if (window.data_manager.data["type"] == "SQLite") {
            yield init_populate_schema (schema);
            reloading = false;
            return;
        }

        _iter = schema.create_iter ();

        if (_iter == null) {
            debug ("not a valid iter");
            return;
        }

        schemas = new Gee.HashMap<int, string> ();
        int i = 1;
        while (_iter.move_next ()) {
            schema_list.append (out iter);
            schema_list.set (iter, Column.SCHEMAS, _iter.get_value_at (0).get_string ());
            schemas.set (i, _iter.get_value_at (0).get_string ());
            i++;
        }
        if (window.data_manager.data["type"] != "PostgreSQL") {
            schema_list_combo.sensitive = true;
        }

        if (window.data_manager.data["type"] == "PostgreSQL") {
            foreach (var entry in schemas.entries) {
                if ("public" == entry.value) {
                    schema_list_combo.set_active (entry.key);
                }
            }
            reloading = false;
            return;
        }

        foreach (var entry in schemas.entries) {
            if (window.data_manager.data["name"] == entry.value) {
                schema_list_combo.set_active (entry.key);
            }
        }

        reloading = false;
    }

    public async Gda.DataModel? get_schema () {
        Gda.DataModel? result = null;
        var query = (window.main.connection_manager.db_type as DataBaseType).show_schema ();

        result = yield window.main.connection_manager.init_select_query (query);

        if (result == null) {
            reloading = false;
            yield reset_schema_combo ();
        }

        return result;
    }

    public async void populate_schema (string? database, Gda.DataModel? schema) {
        yield clear_views ();

        if (database != null && window.data_manager.data["name"] != database && window.data_manager.data["type"] != "PostgreSQL") {
            window.data_manager.data["name"] = database;
            yield update_connection ();
            return;
        }

        if (database == null && window.data_manager.data["type"] == "SQLite" && schema != null) {
            schema_table = schema;
        } else {
            yield get_schema_table (database);
        }

        if (schema_table == null) {
            stop_spinner ();
            return;
        }

        if (scroll.get_child () != null) {
            scroll.remove (scroll.get_child ());
        }

        source_list = new Granite.Widgets.SourceList ();
        source_list.set_filter_func (source_list_visible_func, true);
        tables_category = new Granite.Widgets.SourceList.ExpandableItem (_("TABLES"));
        tables_category.expand_all ();

        Gda.DataModelIter _iter = schema_table.create_iter ();
        int top = 0;
        int count = 0;
        while (_iter.move_next ()) {
            var item = new Sequeler.Partials.DataBaseTable (_iter.get_value_at (0).get_string (), source_list);

            // Get the table rows coutn with an extra query for SQLite
            if (window.data_manager.data["type"] == "SQLite") {
                var table_count = yield get_table_count (item.name);
                Gda.DataModelIter count_iter = table_count.create_iter ();

                while (count_iter.move_next ()) {
                    count = count_iter.get_value_at (0).get_int ();
                    item.badge = count.to_string ();
                }
            } else {
                count = (int) _iter.get_value_at (1).get_long ();
                item.badge = count.to_string ();
            }

            var icon_name = count == 0 ? "table-empty" : "table";
            item.icon = new GLib.ThemedIcon (icon_name);
            item.edited.connect ((new_name) => {
                if (new_name != item.name) {
                    edit_table_name.begin (item.name, new_name);
                }
            });

            tables_category.add (item);
            top++;
        }

        source_list.root.add (tables_category);
        scroll.add (source_list);

        source_list.item_selected.connect (item => {
            if (item == null) {
                return;
            }

            if (window.main.database_view.tabs.selected == 0) {
                window.main.database_view.structure.fill (item.name, database);
            }

            if (window.main.database_view.tabs.selected == 1) {
                window.main.database_view.content.fill (item.name, database, item.badge);
            }

            if (window.main.database_view.tabs.selected == 2) {
                window.main.database_view.relations.fill (item.name, database);
            }
        });

        window.main.database_view.structure.database = database;
        window.main.database_view.content.database = database;
        window.main.database_view.relations.database = database;
        stop_spinner ();
    }

    public async void get_schema_table (string database) {
        var query = (window.main.connection_manager.db_type as DataBaseType).show_table_list (database);

        schema_table = yield window.main.connection_manager.init_select_query (query);
    }

    public async Gda.DataModel? get_table_count (string table) {
        var query = (window.main.connection_manager.db_type as DataBaseType).show_table_list (table);

        return yield window.main.connection_manager.init_select_query (query);
    }

    private async void update_connection () {
        if (window.data_manager.data["type"] == "PostgreSQL") {
            return;
        }

        schema_list_combo.sensitive = false;

        if (scroll.get_child () != null) {
            scroll.remove (scroll.get_child ());
        }

        if (window.main.connection_manager.connection != null && window.main.connection_manager.connection.is_opened ()) {
            //window.main.connection_manager.connection.clear_events_list ();
            window.main.connection_manager.connection.close ();
        }

        var result = new Gee.HashMap<string, string> ();
        try {
            result = yield window.main.connection_manager.init_connection ();
        } catch (ThreadError e) {
            window.main.connection_manager.query_warning (e.message);
        }

        if (result["status"] == "true") {
            reload_schema.begin ();
        } else {
            window.main.connection_manager.query_warning (result["msg"]);
        }
    }

    private async void edit_table_name (string old_name, string new_name) {
        var query = (window.main.connection_manager.db_type as DataBaseType).edit_table_name (old_name, new_name);

        yield window.main.connection_manager.init_query (query);

        yield reload_schema ();
    }

    public void toggle_search_tables () {
        revealer.reveal_child = ! revealer.get_reveal_child ();
        if (revealer.get_reveal_child ()) {
            search.grab_focus_without_selecting ();
        }

        search.text = "";
    }

    public void on_search_tables (Gtk.Entry searchentry) {
        search_text = searchentry.get_text ().down ();
        source_list.refilter ();
        tables_category.expand_all ();
    }

    private bool source_list_visible_func (Sequeler.Widgets.SourceList.Item item) {
        if (search_text == null || item is Sequeler.Widgets.SourceList.ExpandableItem) {
            return true;
        }

        return item.name.down ().contains (search_text);
    }

    private async void clear_views () {
        window.main.database_view.content.reset.begin ();
        window.main.database_view.relations.reset.begin ();
        window.main.database_view.structure.reset.begin ();
    }

    public void show_database_panel () {
        db_panel.new_database ();
        main_revealer.reveal_child = false;
        db_panel.reveal = true;
    }

    public void hide_database_panel () {
        main_revealer.reveal_child = true;
        db_panel.reveal = false;
    }

    public void edit_database_name () {
        db_panel.edit_database (schemas[schema_list_combo.get_active ()]);
        main_revealer.reveal_child = false;
        db_panel.reveal = true;
    }

    public async void create_database (string name) {
        var query = (window.main.connection_manager.db_type as DataBaseType).create_database (name);

        var result = yield window.main.connection_manager.init_query (query);

        if (result == null) {
            return;
        }

        yield reload_schema ();

        hide_database_panel ();
    }

    public async void edit_database (string name) {
        var current_db = schemas[schema_list_combo.get_active ()];

        // Renaming a database is tricky as we can't simply update its name.
        // We need to first create a new database with the chosen name.
        var query = (window.main.connection_manager.db_type as DataBaseType).create_database (name);

        var result = yield window.main.connection_manager.init_query (query);

        if (result == null) {
            return;
        }

        // Then, we need to loop through all the tables and attach them to the new database.
        if (tables_category.n_children > 0) {
            foreach (Sequeler.Widgets.SourceList.Item child in tables_category.children) {
                var tb_result = yield window.main.connection_manager.init_query (
                    (window.main.connection_manager.db_type as DataBaseType).transfer_table (
                        current_db,
                        child.name,
                        name
                    )
                );

                if (tb_result == null) {
                    return;
                }
            }
        }

        // Delete the old database.
        yield window.main.connection_manager.init_query (
            (window.main.connection_manager.db_type as DataBaseType).delete_database (current_db)
        );

        // Update the DataManager to use the newly created database.
        window.data_manager.data["name"] = name;

        yield update_connection ();

        hide_database_panel ();
    }

    public async void delete_database () {
        yield window.main.connection_manager.init_query (
            (window.main.connection_manager.db_type as DataBaseType).delete_database (
                schemas[schema_list_combo.get_active ()]
            )
        );

        yield reload_schema ();

        schema_list_combo.active = 0;
    }
}
