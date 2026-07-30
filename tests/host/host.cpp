// Plain C++ Qt host for a Nim-built plugin.
//
// Deliberately knows nothing about Nim, nimside or Logos: it does what
// ui-host does -- QPluginLoader, then the meta-object system -- and asserts
// that a plugin produced by mkNimPlugin is indistinguishable from a C++ one.

#include <QCoreApplication>
#include <QMetaMethod>
#include <QMetaObject>
#include <QMetaProperty>
#include <QPluginLoader>
#include <QTextStream>

static QTextStream out(stdout);

static int fail(const QString& why)
{
    out << "FAIL: " << why << "\n";
    out.flush();
    return 1;
}

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    if (argc < 2)
        return fail(QStringLiteral("usage: host <plugin>"));

    QPluginLoader loader(QString::fromLocal8Bit(argv[1]));
    if (!loader.load())
        return fail(QStringLiteral("load: ") + loader.errorString());

    QObject* obj = loader.instance();
    if (!obj)
        return fail(QStringLiteral("instance: ") + loader.errorString());

    const QMetaObject* mo = obj->metaObject();
    out << "class: " << mo->className() << "\n";
    if (QLatin1String(mo->className()) != QLatin1String("VanillaNim"))
        return fail(QStringLiteral("unexpected class name"));

    // The property nimside generated from `{.qproperty.}`.
    const int propIdx = mo->indexOfProperty("count");
    if (propIdx < 0)
        return fail(QStringLiteral("no 'count' property"));
    const QMetaProperty prop = mo->property(propIdx);
    if (!prop.hasNotifySignal())
        return fail(QStringLiteral("'count' has no NOTIFY signal"));
    out << "property: " << prop.name() << " : " << prop.typeName()
        << " notify " << prop.notifySignal().methodSignature() << "\n";

    // Property accessors must NOT show up as invokable methods -- moc does not
    // publish them, and anything enumerating slots (QtRemoteObjects, QML)
    // would otherwise see 'count' as both a property and a method.
    for (const char* accessor : { "count()", "setCount(int)", "setCount(qlonglong)" }) {
        if (mo->indexOfMethod(accessor) >= 0)
            return fail(QStringLiteral("accessor %1 leaked into the method table")
                            .arg(QLatin1String(accessor)));
    }
    out << "accessors are not in the method table\n";

    // The declared slot, called the way ui-host would.
    if (mo->indexOfSlot("increment()") < 0)
        return fail(QStringLiteral("no increment() slot"));
    if (!QMetaObject::invokeMethod(obj, "increment"))
        return fail(QStringLiteral("invokeMethod(increment) failed"));

    const int after = obj->property("count").toInt();
    out << "count after increment: " << after << "\n";
    if (after != 1)
        return fail(QStringLiteral("expected count == 1"));

    out << "PASS\n";
    out.flush();
    loader.unload();
    return 0;
}
