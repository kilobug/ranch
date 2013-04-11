Ranch
=====

Ranch 是为TCP协议实现的socket获取池

Goals
-----

Ranch 基于小的代码基和低的延迟，为你提供需要获取TCP链接所需要的一切，然而还能够简单的
作为应用或嵌入到应用中使用。

Ranch 提供模块化的设计，允许你在某个监听器中选择具体的传输层协议(Ranch 允许多个应用同时使用)。
监听器获取和管理连接，并且包含限制并发链接数的实用功能。每个应用都会使用不同的端口，有不同的监听树。
每个应用可以有不同的配置限制。

Ranch 可以在不需要关闭打开连接的情况下更新获取池。


入门
---------------

 *  [阅读向导](http://ninenines.eu/docs/en/ranch/HEAD/guide/introduction)
 *  阅读 `examples/` 目录下的例子
 *  使用 `make docs` 命令生成文档; 打开 `doc/index.html`

支持
-------

 *  Official IRC Channel: #ninenines on irc.freenode.net
 *  [Mailing Lists](http://lists.ninenines.eu)
 *  [Commercial Support](http://ninenines.eu/support)

声明
-------

这个forked的项目，为了自己的阅读方便删除了版权信息，添加了中文注释，不应被用在项目中。