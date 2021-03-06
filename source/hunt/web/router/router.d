/*
 * Hunt - a framework for web and console application based on Collie using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the BSD License.
 *
 */
module hunt.web.router.router;

import std.regex;
import std.string;
import std.experimental.logger;

import hunt.web.router.middleware;
import hunt.web.router.utils;

/**
    The Router Class, Save and Macth the rule, and generte the Pipeline.
*/
final class Router(REQ, RES)
{
    alias HandleDelegate = void delegate(REQ, RES);
    alias Pipeline = PipelineImpl!(REQ, RES);
    alias PipelineFactory = IPipelineFactory!(REQ, RES);
    alias RouterElement = PathElement!(REQ, RES);
    alias RouterMap = ElementMap!(REQ, RES);
    
    alias Request = REQ;
    alias Response = RES;

    /**
        Set The PipelineFactory that create the middleware list for all router rules, before  the router rule's handled execute.
    */
    void setGlobalBeforePipelineFactory(shared PipelineFactory before)
    {
        _gbefore = before;
    }
    /**
        Set The PipelineFactory that create the middleware list for all router rules, after  the router rule's handled execute.
    */
    void setGlobalAfterPipelineFactory(shared PipelineFactory after)
    {
        _gafter = after;
    }

    /**
        Add a Router rule. if config is done, will always erro.
        Params:
            method =  the HTTP method. 
            path   =  the request path.
            handle =  the delegate that handle the request.
            before =  The PipelineFactory that create the middleware list for the router rules, before  the router rule's handled execute.
            after  =  The PipelineFactory that create the middleware list for the router rules, after  the router rule's handled execute.
        Returns: the rule's element class. if can not add the rule will return null.
    */
    RouterElement addRouter(string method, string path, HandleDelegate handle,
        shared PipelineFactory before = null, shared PipelineFactory after = null)
    {
        if (condigDone)
            return null;
        RouterMap map = _map.get(method, null);
        if (!map)
        {
            map = new RouterMap(this);
            _map[method] = map;
        }
        trace("add Router method: ", method);
        return map.add(path, handle, before, after);
    }
 
    /**
        Match the rule.if config is not done, will always erro.
        Params:
            method = the method group.
            path   = the path to match.
        Returns: 
            the pipeline has the Global MiddleWare ,Rule MiddleWare, Rule handler .
            the list is : Before Global MiddleWare -> Before Rule MiddleWare -> Rule handler -> After Rule MiddleWare -> After Global MiddleWare
            if don't match will  return null.
    */
    Pipeline match(string method, string path)
    {
        Pipeline pipe = null;
        if (!condigDone)
            return pipe;
        RouterMap map = _map.get(method, null);
        if (!map)
            return pipe;
        pipe = map.match(path);
        return pipe;
    }

    /**
        Get PipelineFactory that create the middleware list for all router rules.
    */
    Pipeline getGlobalBrforeMiddleware()
    {
        if (_gbefore)
            return _gbefore.newPipeline();
        else
            return null;
    }

    /**
        Get The PipelineFactory that create the middleware list for all router rules.
    */
    Pipeline getGlobalAfterMiddleware()
    {
        if (_gafter)
            return _gafter.newPipeline();
        else
            return null;
    }

    /**
        get config is done.
        if config is done, the add rule will erro.
        else math rule will erro.
    */
    @property bool condigDone()
    {
        return _configDone;
    }

    /// set config done.
    void done()
    {
        _configDone = true;
    }

private:
    shared PipelineFactory _gbefore = null;
    shared PipelineFactory _gafter = null;
    RouterMap[string] _map;
    bool _configDone = false;
}


/**
    A rule elment class.
*/
class PathElement(REQ, RES)
{
    alias HandleDelegate = void delegate(REQ, RES);
    alias Pipeline = PipelineImpl!(REQ, RES);
    alias PipelineFactory = IPipelineFactory!(REQ, RES);

    /**
        Constructor and set the path.
    */
    this(string path)
    {
        _path = path;
    }

    /// get the path
    final @property path() const
    {
        return _path;
    }

    /// get the handle.
    final @property handler() const
    {
        return _handler;
    }

    /// set the handle
    final @property handler(HandleDelegate handle)
    {
        _handler = handle;
    }

    /// get the befor pipeline.
    final Pipeline getBeforeMiddleware()
    {
        if (_before)
            return _before.newPipeline();
        else
            return null;
    }

    /// get the after pipeline.
    final Pipeline getAfterMiddleware()
    {
        if (_after)
            return _after.newPipeline();
        else
            return null;
    }

    /**
        Set The PipelineFactory that create the middleware list for this rules, before  the router rule's handled execute.
    */
    final void setBeforePipelineFactory(shared PipelineFactory before)
    {
        _before = before;
    }

    /**
        Set The PipelineFactory that create the middleware list for this rules, after  the router rule's handled execute.
    */
    final void setAfterPipelineFactory(shared PipelineFactory after)
    {
        _after = after;
    }
    
    PathElement!(REQ, RES) macth(string path, Pipeline pipe)
    {
        return this;
    }

private:
    string _path;
    HandleDelegate _handler = null;
    shared PipelineFactory _before = null;
    shared PipelineFactory _after = null;
}

private:

final class RegexElement(REQ, RES) : PathElement!(REQ, RES)
{
    this(string path)
    {
        super(path);
    }

    override PathElement!(REQ, RES) macth(string path, Pipeline pipe)
    {
        //writeln("the path is : ", path, "  \t\t regex is : ", _reg);
        auto rg = regex(_reg, "s");
        auto mt = matchFirst(path, rg);
        if (!mt)
        {
            return null;
        }
        foreach (attr; rg.namedCaptures)
        {
            pipe.addMatch(attr, mt[attr]);
        }
        return this;
    }

private:
    bool setRegex(string reg)
    {
        if (reg.length == 0)
            return false;
        _reg = buildRegex(reg);
        if (_reg.length == 0)
            return false;
        return true;
    }

    string _reg;
}

final class RegexMap(REQ, RES)
{
    alias RElement = RegexElement!(REQ, RES);
    alias PElement = PathElement!(REQ, RES);
    alias RElementMap = RegexMap!(REQ, RES);
    alias Pipeline = PipelineImpl!(REQ, RES);

    this(string path)
    {
        _path = path;
    }

    PElement add(RElement ele, string preg)
    {
        string rege;
        string str = getFirstPath(preg, rege);
        //writeln("RegexMap add : path = ", ele.path, " \n\tpreg = ", preg, "\n\t str = ", str,
        //       "\n\t rege = ", rege, "\n");
        if (str.length == 0)
        {
            ele.destroy;
            return null;
        }
        if (isHaveRegex(str))
        {
            //  writeln("set regex is  : ", preg);
            if (!ele.setRegex(preg))
                return null;

            bool isHas = false;
            for (int i = 0; i < _list.length; ++i) //添加的时候去重
            {
                if (_list[i].path == ele.path)
                {
                    isHas = true;
                    auto tele = _list[i];
                    _list[i] = ele;
                    tele.destroy;
                }
            }
            if (!isHas)
            {
                _list ~= ele;
            }
            return ele;
        }
        else
        {
            RElementMap map = _map.get(str, null);
            if (!map)
            {
                map = new RElementMap(str);
                _map[str] = map;
            }
            return map.add(ele, rege);
        }
    }

    PElement match(string path, Pipeline pipe)
    {
        // writeln(" \t\tREGEX macth path:  ", path);
        if (path.length == 0)
            return null;
        string lpath;
        string frist = getFirstPath(path, lpath);
        if (frist.length == 0)
            return null;
        RElementMap map = _map.get(frist, null);
        if (map)
        {
            return map.match(lpath, pipe);
        }
        else
        {
            foreach (ele; _list)
            {
                auto element = ele.macth(path, pipe);
                if (element)
                {
                    return element;
                }
            }
        }
        return null;
    }

private:
    RElementMap[string] _map;
    RElement[] _list;
    string _path;
}

final class ElementMap(REQ, RES)
{
    alias RElement = RegexElement!(REQ, RES);
    alias PElement = PathElement!(REQ, RES);
    alias RElementMap = RegexMap!(REQ, RES);
    alias Pipeline = PipelineImpl!(REQ, RES);
    alias Route = Router!(REQ, RES);
    alias HandleDelegate = void delegate(REQ, RES);
    alias PipelineFactory = IPipelineFactory!(REQ, RES);

    this(Route router)
    {
        _router = router;
        _regexMap = new RElementMap("/");
    }

    PElement add(string path, HandleDelegate handle, shared PipelineFactory before,
        shared PipelineFactory after)
    {
        if (isHaveRegex(path))
        {
            auto ele = new RElement(path);
            ele.setAfterPipelineFactory(after);
            ele.setBeforePipelineFactory(before);
            ele.handler = handle;
            return _regexMap.add(ele, path);
        }
        else
        {
	    trace("add function: ", path);
            auto ele = new PElement(path);
            ele.setAfterPipelineFactory(after);
            ele.setBeforePipelineFactory(before);
            ele.handler = handle;
            _pathMap[path] = ele;
            return ele;
        }
    }

    Pipeline match(string path)
    {
        Pipeline pipe = new Pipeline();

        PElement element = _pathMap.get(path, null);
        
        if (!element)
        {
            element = _regexMap.match(path, pipe);
        }

        if (element)
        {
            pipe.append(_router.getGlobalBrforeMiddleware());
            pipe.append(element.getBeforeMiddleware());
            pipe.addHandler(element.handler);
            pipe.append(element.getAfterMiddleware());
            pipe.append(_router.getGlobalAfterMiddleware());

        }
        else
        {
            pipe.destroy;
            pipe = null;
        }
        return pipe;
    }

private:
    Route _router;
    PElement[string] _pathMap;
    RElementMap _regexMap;
}

unittest
{
    import std.functional;
    import std.stdio;

    class Test
    {
        int gtest = 0;
    }

    alias Route = Router!(Test, int);
    class TestMiddleWare : IMiddleWare!(Test, int)
    {
        override void handle(Context ctx, Test a, int b)
        {
            a.gtest += 1;
            writeln("\tIMiddleWare handle : a.gtest : ", a.gtest);
            ctx.next(a, b);
        }
    }

    void testFun(Test a, int b)
    {
        ++a.gtest;
    }

    shared class Factor : IPipelineFactory!(Test, int)
    {
        alias Pipeline = PipelineImpl!(Test, int);
        override Pipeline newPipeline()
        {
            auto pip = new Pipeline();
            pip.addHandler(new TestMiddleWare());
            pip.addHandler(new TestMiddleWare());
            return pip;
        }
    }

    Test a = new Test();

    Route router = new Route();

    router.setGlobalBeforePipelineFactory(new shared Factor());
    router.setGlobalAfterPipelineFactory(new shared Factor());

    auto ele = router.addRouter("get", "/file", toDelegate(&testFun),
        new shared Factor(), new shared Factor());
    assert(ele !is null);
    ele = router.addRouter("get",
        "/file/{:[0-9a-z]{1}}/{d2:[0-9a-z]{2}}/{imagename:\\w+\\.\\w+}",
        toDelegate(&testFun), new shared Factor(), new shared Factor());
    assert(ele !is null);
    ele = router.addRouter("post",
        "/file/{d1:[0-9a-z]{1}}/{d2:[0-9a-z]{2}}/{imagename:\\w+\\.\\w+}", toDelegate(&testFun));
    assert(ele !is null);
    router.done();

    auto pipe = router.match("post", "/file");
    assert(pipe is null);
    pipe = router.match("post", "/");
    assert(pipe is null);

    pipe = router.match("get", "/file");
    assert(pipe !is null);
    a.gtest = 0;
    pipe.handleActive(a, 0);
    assert(a.gtest == 9);

    pipe = router.match("post", "/file/2/34/ddd.jpg");
    assert(pipe !is null);
    assert(pipe.matchData.length == 3);
    a.gtest = 0;
    pipe.handleActive(a, 0);
    assert(a.gtest == 5);

    pipe = router.match("get", "/file/2/34/ddd.jpg");
    assert(pipe !is null);
    assert(pipe.matchData.length == 2);
    a.gtest = 0;
    pipe.handleActive(a, 0);
    assert(a.gtest == 9);

}
