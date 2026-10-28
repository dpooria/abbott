package abbott

import pixbuf "odin-gtk/gdk-pixbuf"
import "odin-gtk/glib"
import "odin-gtk/glib/gio"
import gobj "odin-gtk/glib/gobject"
import "odin-gtk/gtk"

judy_picture :: proc() -> ^gtk.Widget {
    svg :: #load("assets/judy.svg")
    loader := pixbuf.pixbuf_loader_new()
    defer gobj.object_unref(loader)
    if !pixbuf.pixbuf_loader_write(loader, cast(^u8)raw_data(svg), u64(len(svg)), nil) {
        pixbuf.pixbuf_loader_close(loader, nil)
        return gtk.image_new_from_icon_name("accessories-dictionary-symbolic")
    }
    pixbuf.pixbuf_loader_close(loader, nil)
    image := gtk.image_new_from_pixbuf(pixbuf.pixbuf_loader_get_pixbuf(loader))
    gtk.image_set_pixel_size(gtk.IMAGE(image), 120)
    gtk.widget_set_halign(image, .START)
    gtk.widget_set_tooltip_text(image, "A little nod to Judy Abbott and Daddy-Long-Legs.")
    return image
}

register_judy_icon :: proc() {
    data :: #load(".build/abbott.gresource")
    bytes := glib.bytes_new_static(raw_data(data), u64(len(data)))
    defer glib.bytes_unref(bytes)
    resource := gio.resource_new_from_data(bytes, nil)
    if resource == nil {return}
    gio.resources_register(resource)
    gio.resource_unref(resource)
    theme := gtk.icon_theme_get_for_display(gtk.gdk_display_get_default())
    gtk.icon_theme_add_resource_path(theme, "/io/abbott/icons")
}


judy_quotes := [?]string {
    "Most people don’t live; they just race.",
    "It isn’t the great big pleasures that count the most; it’s making a great deal out of the little ones",
    "I’m going to enjoy every second, and I’m going to KNOW I’m enjoying it while I’m enjoying it.",
    "Youth has nothing to do with birthdays, only with ALIVEDNESS of spirit",
    "If you just want a thing hard enough and keep on trying, you do get it in the end.",
    "I’d rather know you than French.",
    "The world is full of happiness, and plenty to go round, if you are only willing to take the kind that comes your way.",
    "I’ve decided to sit down by the way and pile up a lot of little happinesses, even if I never become a Great Author.",
    "No one can ever accuse me of being a pessimist!",
    "My peace of mind is gone for ever-but anyway, I never cared much for just plain peace.",
    "It’s raining cats and dogs tonight. Two puppies and a kitten have just landed on the window-sill.",
}
