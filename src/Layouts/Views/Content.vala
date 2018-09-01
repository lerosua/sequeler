/*
* Copyright (c) 2011-2018 Alecaddd (http://alecaddd.com)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Alessandro "Alecaddd" Castellani <castellani.ale@gmail.com>
*/

public class Sequeler.Layouts.Views.Content : Gtk.Grid {
	public weak Sequeler.Window window { get; construct; }

	public Gtk.ScrolledWindow scroll;
	public Gtk.Label result_message;
	public Sequeler.Partials.HeaderBarButton page_prev_btn;
	public Sequeler.Partials.HeaderBarButton page_next_btn;

	private string _table_name = "";

	public string table_name {
		get { return _table_name; }
		set { _table_name = value; }
	}

	private string _database = "";

	public string database {
		get { return _database; }
		set { _database = value; }
	}

	public Content (Sequeler.Window main_window) {
		Object (
			orientation: Gtk.Orientation.VERTICAL,
			window: main_window
		);
	}

	construct {
		scroll = new Gtk.ScrolledWindow (null, null);
		scroll.hscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
		scroll.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
		scroll.expand = true;

		var info_bar = new Gtk.Grid ();
		info_bar.get_style_context ().add_class ("library-toolbar");
		info_bar.attach (build_pagination (), 0, 0, 1, 1);
		info_bar.attach (new Gtk.Separator (Gtk.Orientation.VERTICAL), 1, 0, 1, 1);
		info_bar.attach (build_results_msg (), 2, 0, 1, 1);
		info_bar.attach (build_reload_btn (), 3, 0, 1, 1);

		attach (scroll, 0, 0, 1, 1);
		attach (info_bar, 0, 1, 1, 1);

		placeholder ();
	}

	public Gtk.Grid build_pagination () {
		var page_grid = new Gtk.Grid ();

		page_prev_btn = new Sequeler.Partials.HeaderBarButton ("go-previous-symbolic", _("Previous Page"));
		page_prev_btn.clicked.connect (go_prev_page);
		page_prev_btn.halign = Gtk.Align.START;
		page_prev_btn.sensitive = false;

		page_next_btn = new Sequeler.Partials.HeaderBarButton ("go-next-symbolic", _("Next Page"));
		page_next_btn.clicked.connect (go_next_page);
		page_next_btn.halign = Gtk.Align.END;
		page_next_btn.sensitive = false;

		var pages_count = new Gtk.Label ("0 Pages");
		pages_count.margin = 7;

		page_grid.attach (page_prev_btn, 0, 0, 1, 1);
		page_grid.attach (new Gtk.Separator (Gtk.Orientation.VERTICAL), 1, 0, 1, 1);
		page_grid.attach (pages_count, 2, 0, 1, 1);
		page_grid.attach (new Gtk.Separator (Gtk.Orientation.VERTICAL), 3, 0, 1, 1);
		page_grid.attach (page_next_btn, 4, 0, 1, 1);

		return page_grid;
	}

	public Gtk.Label build_results_msg () {
		result_message = new Gtk.Label (_("No Results Available"));
		result_message.halign = Gtk.Align.START;
		result_message.margin = 7;
		result_message.margin_top = 6;
		result_message.hexpand = true;
		result_message.wrap = true;

		return result_message;
	}

	private Gtk.Button build_reload_btn () {
		var reload_btn = new Sequeler.Partials.HeaderBarButton ("view-refresh-symbolic", _("Reload Results"));
		reload_btn.clicked.connect (reload_results);
		reload_btn.halign = Gtk.Align.END;

		return reload_btn;
	}

	public void placeholder () {
		var intro = new Granite.Widgets.Welcome (_("Select Table"), _("Select a table from the left sidebar to activate this view."));
		scroll.add (intro);
	}

	public void clear () {
		if (scroll.get_child () != null) {
			scroll.remove (scroll.get_child ());
		}
	}

	public void reset () {
		if (scroll.get_child () != null) {
			scroll.remove (scroll.get_child ());
		}

		result_message.label = _("No Results Available");
		table_name = "";
		database = "";
		placeholder ();

		scroll.show_all ();
	}

	public void fill (string? table, string? db_name = null) {
		if (table == null) {
			return;
		}

		if (table == _table_name && db_name == _database) {
			debug ("Already loaded");
			return;
		}

		table_name = table;
		database = db_name;

		var query = (window.main.connection.db_type as DataBaseType).show_table_content (table);

		var table_content = get_table_content (query);

		if (table_content == null) {
			return;
		}

		var result_data = new Sequeler.Partials.TreeBuilder (table_content, window);
		result_message.label = _("%d Entries").printf (table_content.get_n_rows ());

		clear ();

		scroll.add (result_data);
		scroll.show_all ();
	}

	public void reload_results () {
		if (table_name == "") {
			return;
		}

		var query = (window.main.connection.db_type as DataBaseType).show_table_content (table_name);

		var table_content = get_table_content (query);

		if (table_content == null) {
			return;
		}

		var result_data = new Sequeler.Partials.TreeBuilder (table_content, window);
		result_message.label = table_content.get_n_rows ().to_string () + _(" Entries");

		clear ();

		scroll.add (result_data);
		scroll.show_all ();
	}

	private Gda.DataModel? get_table_content (string query) {
		Gda.DataModel? result = null;
		var error = "";

		var loop = new MainLoop ();
		window.main.connection.init_select_query.begin (query, (obj, res) => {
			try {
				result = window.main.connection.init_select_query.end (res);
			} catch (ThreadError e) {
				error = e.message;
				result = null;
			}
			loop.quit ();
		});

		loop.run ();

		if (error != "") {
			window.main.connection.query_warning (error);
			result_message.label = error;
			return null;
		}

		return result;
	}

	public void go_prev_page () {

	}

	public void go_next_page () {

	}
}
