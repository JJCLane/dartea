part of dartea;

const rootKey = const Key('dartea_root_widget');

class DarteaWidget<TModel, TMsg, TSub> extends StatefulWidget {
  final Program<TModel, TMsg, TSub> program;

  DarteaWidget(this.program, {Key key}) : super(key: key ?? rootKey);
  @override
  State<StatefulWidget> createState() =>
      new _DrateaProgramState<TModel, TMsg, TSub>();
}

class _DrateaProgramState<TModel, TMsg, TSub>
    extends State<DarteaWidget<TModel, TMsg, TSub>>
    with WidgetsBindingObserver {
  TModel _currentModel;
  final StreamController<TMsg> _mainLoopController = new StreamController();
  final StreamController<AppLifecycleState> _lifeCycleController =
      new StreamController();
  StreamSubscription<Upd<TModel, TMsg>> _appLoopSub;
  TSub _appSubHolder;

  Dispatch<TMsg> get dispatcher => (m) {
        if (!_mainLoopController.isClosed) {
          _mainLoopController.add(m);
        }
      };

  Program<TModel, TMsg, TSub> get program => widget.program;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    var initial = program.init();
    var initialModel = initial.model;
    var initialEffects = new List<Effect<TMsg>>();
    initialEffects.addAll(initial.effects);
    var newModel = initialModel;

    final lifeCycleStream = _lifeCycleController.stream
        .map((x) =>
            newModel != null ? program.lifeCycleUpdate(x, newModel) : null)
        .where((x) => x != null);

    final mainLoopStream = _mainLoopController.stream
        .map((msg) => msg != null && newModel != null
            ? program.update(msg, newModel)
            : null)
        .where((x) => x != null);

    final updStream = StreamGroup.merge([lifeCycleStream, mainLoopStream]);

    _appLoopSub = updStream
        .handleError((e, st) => program.onError(st, e))
        .listen((updates) {
      newModel = updates.model;
      if (newModel != _currentModel) {
        setState(() {
          _currentModel = newModel;
        });
      }
      _appSubHolder = program.sub(_appSubHolder, dispatcher, newModel);
      for (var effect in updates.effects) {
        effect(dispatcher);
      }
    });

    setState(() {
      _currentModel = newModel;
    });
    _appSubHolder = program.sub(_appSubHolder, dispatcher, newModel);
    initialEffects.forEach((effect) => effect(dispatcher));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appLoopSub?.cancel();
    _mainLoopController.close();
    _lifeCycleController.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifeCycleController.add(state);
  }

  @override
  Widget build(BuildContext context) => _currentModel == null
      ? new Container()
      : program.view(context, dispatcher, _currentModel);
}
