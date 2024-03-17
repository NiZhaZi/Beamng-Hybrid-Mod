#include "dialog.h"
#include "./ui_dialog.h"
#include<bits/stdc++.h>
#include <QClipboard>
#include <QApplication>

Dialog::Dialog(QWidget *parent)
    : QDialog(parent)
    , ui(new Ui::Dialog)
{
    ui->setupUi(this);
    Qt::WindowFlags windowFlag  = Qt::Dialog;
    windowFlag                  |= Qt::WindowMinimizeButtonHint;
    windowFlag                  |= Qt::WindowMaximizeButtonHint;
    windowFlag                  |= Qt::WindowCloseButtonHint;
        setWindowFlags(windowFlag);
}

Dialog::~Dialog()
{
    delete ui;
}

float torque = 150.00, maxPower = 200.00, decrease = 5.00;//最大扭矩torque，最大功率maxPower，扭矩衰减decrease。
int maxRPM = 15000;//最大转速maxRPM。

QString maxN = "";
QString HP = "";

std::string table0 = "";

void count0(){

    table0 = "";

    float N;//最大功率时转速N。

    float currentTorque = torque;

    N = 9549 * maxPower / torque;//计算最大功率时转速N。
    maxN = QString::number(N);
    float hp = maxPower * 1.341;//计算最大功率对应公制马力hp。
    HP = QString::number(hp);

    for(int i = 0; i <= maxRPM; i += 500) {
        if (i >= N) {
            currentTorque = (9549 * maxPower / i);
            currentTorque *= (1 - decrease / 100);
        }
        std::stringstream ss;
        ss << std::fixed << std::setprecision(2) << currentTorque;
        std::string CT = ss.str();
        table0 += "[";
        table0 += std::to_string(i);
        table0 += ", ";
        table0 += CT;
        table0 += "],";
        table0 += "\n";
    }
}

void Dialog::on_pushButton_clicked()//确认按钮
{
    count0();
    QString tablestr = QString::fromStdString(table0);
    ui -> textBrowser -> setText(tablestr);
    ui -> textBrowser_2 -> setText(maxN);
    ui -> textBrowser_3 -> setText(HP);
}


void Dialog::on_pushButton_2_clicked()//重置按钮
{
    ui -> lineEdit -> clear();
    ui -> lineEdit_2 -> clear();
    ui -> lineEdit_3 -> clear();
    ui -> lineEdit_4 -> clear();
    ui -> textBrowser -> clear();
    ui -> textBrowser_2 -> clear();
    ui -> textBrowser_3 -> clear();
}

void Dialog::on_pushButton_3_clicked()//退出按钮
{
    close();
}

void Dialog::on_pushButton_4_clicked()//复制按钮
{
    count0();
    QString tablestr0 = QString::fromStdString(table0);
    QClipboard *clip = QApplication::clipboard();
    clip->setText(tablestr0);

}




void Dialog::on_lineEdit_editingFinished()
{
    torque = 150.00;
    QString To = ui->lineEdit->text();
    torque = To.toFloat();
}


void Dialog::on_lineEdit_2_editingFinished()
{
    maxPower = 200.00;
    QString Po = ui->lineEdit_2->text();
    maxPower = Po.toFloat();
}


void Dialog::on_lineEdit_3_editingFinished()
{
    maxRPM = 15000;
    QString RPM0 = ui->lineEdit_3->text();
    maxRPM = RPM0.toInt();
}


void Dialog::on_lineEdit_4_editingFinished()
{
    decrease = 5.00;
    QString DEC = ui->lineEdit_4->text();
    decrease = DEC.toFloat();
}

